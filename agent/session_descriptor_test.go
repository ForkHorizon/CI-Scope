package agent

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestSessionDescriptorIsAtomicAndSecretFree(t *testing.T) {
	root := t.TempDir()
	descriptor := SessionDescriptor{
		MachineID: "machine", BootID: "boot", AgentInstanceID: "agent", SessionID: "session",
		SessionEpoch: 4, LocalOwnerEpoch: 7, FencingToken: "fence", SocketPath: filepath.Join(root, "agent.sock"),
	}
	if err := WriteSessionDescriptor(root, descriptor); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, sessionDescriptorName)
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("descriptor mode = %o", info.Mode().Perm())
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var decoded SessionDescriptor
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded != descriptor {
		t.Fatalf("descriptor = %+v, want %+v", decoded, descriptor)
	}
	if err := RemoveSessionDescriptor(root); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("descriptor remains after removal: %v", err)
	}
}
