package agent

import (
	"context"
	"errors"
	"strings"
)

func (c *SchedulerServerClient) ClaimNext(ctx context.Context, requestID, poolIdentity string) (SchedulerClaimResponse, error) {
	// poolIdentity is retained in the client seam for source compatibility
	// while dispatch.next derives routing from durable Web pending work.
	_ = poolIdentity
	response, err := c.request(ctx, requestID, SchedulerDispatchNextPath, map[string]any{
		"type": "dispatch.next",
	})
	if err != nil {
		return SchedulerClaimResponse{}, err
	}
	var result SchedulerClaimResponse
	if err := decodeSchedulerPayload(response, &result); err != nil {
		return SchedulerClaimResponse{}, err
	}
	if result.Claimed {
		if err := validateSchedulerReservation(result.Reservation); err != nil {
			return SchedulerClaimResponse{}, err
		}
	}
	return result, nil
}

func (c *SchedulerServerClient) Reconcile(ctx context.Context, requestID string, reservation SchedulerReservation, intent string) (SchedulerReconcileResponse, error) {
	response, err := c.request(ctx, requestID, SchedulerReconcilePath, map[string]any{
		"type": "scheduler.reconcile", "intent": intent, "reservation": reservation,
	})
	if err != nil {
		return SchedulerReconcileResponse{}, err
	}
	var result SchedulerReconcileResponse
	if err := decodeSchedulerPayload(response, &result); err != nil {
		return SchedulerReconcileResponse{}, err
	}
	return result, nil
}

func (c *SchedulerServerClient) Status(ctx context.Context, requestID string, reservation SchedulerReservation) (SchedulerStatusResponse, error) {
	id := strings.TrimSpace(reservation.ReservationID)
	if id == "" || strings.ContainsAny(id, "/?#") {
		return SchedulerStatusResponse{}, errors.New("invalid scheduler reservation ID")
	}
	response, err := c.request(ctx, requestID, SchedulerReservationPathRoot+id+"/status", map[string]any{
		"type": "scheduler.reservation.status", "reservation": reservation,
	})
	if err != nil {
		return SchedulerStatusResponse{}, err
	}
	var result SchedulerStatusResponse
	if err := decodeSchedulerPayload(response, &result); err != nil {
		return SchedulerStatusResponse{}, err
	}
	return result, nil
}

func (c *SchedulerServerClient) Release(ctx context.Context, requestID string, reservation SchedulerReservation) (SchedulerStatusResponse, error) {
	id := strings.TrimSpace(reservation.ReservationID)
	if id == "" || strings.ContainsAny(id, "/?#") {
		return SchedulerStatusResponse{}, errors.New("invalid scheduler reservation ID")
	}
	response, err := c.request(ctx, requestID, SchedulerReservationPathRoot+id+"/release", map[string]any{
		"type": "scheduler.reservation.release", "reservation": reservation,
	})
	if err != nil {
		return SchedulerStatusResponse{}, err
	}
	var result SchedulerStatusResponse
	if err := decodeSchedulerPayload(response, &result); err != nil {
		return SchedulerStatusResponse{}, err
	}
	return result, nil
}

func (c *SchedulerServerClient) Recover(ctx context.Context, requestID string, reservation SchedulerReservation) (SchedulerStatusResponse, error) {
	id := strings.TrimSpace(reservation.ReservationID)
	if id == "" || strings.ContainsAny(id, "/?#") {
		return SchedulerStatusResponse{}, errors.New("invalid scheduler reservation ID")
	}
	response, err := c.request(ctx, requestID, SchedulerReservationPathRoot+id+"/recover", map[string]any{
		"type": "scheduler.reservation.recover", "reservation": reservation,
	})
	if err != nil {
		return SchedulerStatusResponse{}, err
	}
	var result SchedulerStatusResponse
	if err := decodeSchedulerPayload(response, &result); err != nil {
		return SchedulerStatusResponse{}, err
	}
	return result, nil
}

func (c *SchedulerServerClient) Register(ctx context.Context, requestID string, reservation SchedulerReservation) error {
	id := strings.TrimSpace(reservation.ReservationID)
	if id == "" || strings.ContainsAny(id, "/?#") {
		return errors.New("invalid scheduler reservation ID")
	}
	_, err := c.request(ctx, requestID, "/api/ci/v2/reservations/"+id+"/register", map[string]any{
		"type": "reservation.register", "reservationId": id, "runnerCorrelation": reservation.Correlation,
	})
	return err
}
