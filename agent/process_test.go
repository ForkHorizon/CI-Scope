package agent

import (
	"os"
	"path/filepath"
	"testing"
)

func TestProcessIdentityRequiresAllOwnershipFacts(t *testing.T) {
	want := ProcessIdentity{PID: 10, StartTime: 20, ProcessGroupID: 30, Executable: "/runner", RunnerInstanceID: "r"}
	if !want.Matches(want) {
		t.Fatal("identity should match")
	}
	wrong := want
	wrong.StartTime++
	if want.Matches(wrong) {
		t.Fatal("pid reuse must fail start-time check")
	}
}

func TestCleanupWorkspaceRejectsSymlinkAndEscape(t *testing.T) {
	root := t.TempDir()
	inside := filepath.Join(root, "inside")
	if err := os.Mkdir(inside, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := CleanupWorkspace(root, inside); err != nil {
		t.Fatal(err)
	}
	outside := t.TempDir()
	link := filepath.Join(root, "link")
	if err := os.Symlink(outside, link); err != nil {
		t.Fatal(err)
	}
	if err := CleanupWorkspace(root, link); err == nil {
		t.Fatal("symlink cleanup should fail")
	}
	if err := ValidateWorkspace(root, filepath.Join(root, "..", filepath.Base(outside))); err == nil {
		t.Fatal("escape should fail")
	}
}
