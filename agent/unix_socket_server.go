package agent

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"net"
	"time"
)

func (r *UnixSocketRuntime) handleConnection(raw net.Conn) {
	defer raw.Close()
	_ = raw.SetDeadline(time.Now().Add(r.config.IOTimeout))
	conn, ok := raw.(*net.UnixConn)
	if !ok {
		return
	}
	uid, err := unixPeerUID(conn)
	if err != nil || r.config.PeerUIDValidator == nil || !r.config.PeerUIDValidator(uid) {
		return
	}
	frame, err := readUnixFrame(bufio.NewReaderSize(conn, minInt(r.config.MaxFrameBytes, 64<<10)), r.config.MaxFrameBytes)
	if err != nil {
		return
	}
	request, err := decodeSocketRequest(frame)
	if err != nil {
		_ = r.writeResponse(conn, r.errorResponse("unknown", "", "rejected", "malformed_frame"))
		return
	}
	if err := r.validateRequestContext(request); err != nil {
		_ = r.writeResponse(conn, r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "invalid_fencing_context"))
		return
	}
	response := r.dispatch(request)
	_ = r.writeResponse(conn, response)
}

func minInt(left, right int) int {
	if left < right {
		return left
	}
	return right
}

func readUnixFrame(reader *bufio.Reader, maximum int) ([]byte, error) {
	frame := make([]byte, 0, minInt(maximum, 4096))
	for {
		part, err := reader.ReadSlice('\n')
		frame = append(frame, part...)
		if len(frame) > maximum {
			return nil, errors.New("unix socket frame is too large")
		}
		if err == nil {
			if len(frame) == 1 {
				return nil, errors.New("unix socket frame is empty")
			}
			return frame, nil
		}
		if errors.Is(err, bufio.ErrBufferFull) {
			continue
		}
		return nil, err
	}
}

func decodeSocketRequest(frame []byte) (SocketRequestEnvelope, error) {
	var request SocketRequestEnvelope
	if err := json.Unmarshal(frame[:len(frame)-1], &request); err != nil {
		return SocketRequestEnvelope{}, err
	}
	if request.ProtocolVersion != ServerProtocolVersion || request.RequestID == "" || request.PayloadHash == "" || len(request.Payload) == 0 {
		return SocketRequestEnvelope{}, errors.New("invalid socket request metadata")
	}
	if request.Identity == nil && request.Session == nil {
		return SocketRequestEnvelope{}, errors.New("socket request identity is missing")
	}
	if request.Identity != nil && request.Session != nil {
		return SocketRequestEnvelope{}, errors.New("socket request has duplicate identity contexts")
	}
	var payload any
	if err := json.Unmarshal(request.Payload, &payload); err != nil {
		return SocketRequestEnvelope{}, err
	}
	hash, err := HashPayload(payload)
	if err != nil || hash != request.PayloadHash {
		return SocketRequestEnvelope{}, errors.New("socket request payload hash mismatch")
	}
	if request.Identity != nil {
		if request.Identity.MachineID == "" || request.Identity.BootID == "" || request.Identity.AgentInstanceID == "" || request.Identity.SessionID == "" || request.Fencing.SessionEpoch == 0 {
			return SocketRequestEnvelope{}, errors.New("socket request identity is incomplete")
		}
		request.Session = &SocketSessionContext{
			MachineID: request.Identity.MachineID, BootID: request.Identity.BootID,
			AgentInstanceID: request.Identity.AgentInstanceID, SessionID: request.Identity.SessionID,
			SessionEpoch: request.Fencing.SessionEpoch,
		}
	}
	if request.Session.MachineID == "" || request.Session.BootID == "" || request.Session.AgentInstanceID == "" || request.Session.SessionID == "" || request.Session.SessionEpoch == 0 || request.Fencing.LocalOwnerEpoch == 0 || request.Fencing.SessionEpoch != request.Session.SessionEpoch {
		return SocketRequestEnvelope{}, errors.New("socket request session or fencing is incomplete")
	}
	return request, nil
}

func (r *UnixSocketRuntime) writeResponse(conn *net.UnixConn, response SocketResponseEnvelope) error {
	data, err := json.Marshal(response)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if len(data) > r.config.MaxFrameBytes {
		return errors.New("unix socket response is too large")
	}
	for len(data) > 0 {
		written, writeErr := conn.Write(data)
		if writeErr != nil {
			return writeErr
		}
		if written == 0 {
			return io.ErrShortWrite
		}
		data = data[written:]
	}
	return nil
}

func (r *UnixSocketRuntime) validateRequestContext(request SocketRequestEnvelope) error {
	if request.Session == nil {
		return errors.New("socket request session is missing")
	}
	if request.Session.MachineID != r.config.Identity.MachineID ||
		request.Session.BootID != r.config.Identity.BootID ||
		request.Session.AgentInstanceID != r.config.Identity.AgentInstanceID ||
		request.Session.SessionID != r.config.Identity.SessionID ||
		request.Session.SessionEpoch != r.config.ServerSessionEpoch {
		return errors.New("socket request session does not match runtime")
	}
	if request.Fencing.LocalOwnerEpoch != r.config.LocalEpoch ||
		request.Fencing.SessionEpoch != r.config.ServerSessionEpoch ||
		request.Fencing.FencingToken != r.config.FencingToken {
		return errors.New("socket request fencing does not match runtime")
	}
	if r.config.RunnerInstanceID != "" && request.Fencing.RunnerInstanceID != r.config.RunnerInstanceID {
		return errors.New("socket request runner ownership does not match runtime")
	}
	if request.Identity != nil && *request.Identity != r.config.Identity {
		return errors.New("socket request identity does not match runtime")
	}
	return nil
}
