// Tests for detecting the tools this device offers to the gate queue.
package main

import (
	"errors"
	"reflect"
	"testing"
)

func lookPathWith(present ...string) func(string) (string, error) {
	set := map[string]bool{}
	for _, name := range present {
		set[name] = true
	}
	return func(name string) (string, error) {
		if set[name] {
			return "/usr/bin/" + name, nil
		}
		return "", errors.New("not found")
	}
}

func TestDetectsToolsOnPath(t *testing.T) {
	t.Setenv(envCapabilities, "")
	// An empty explicit value is still explicit: it means "this device offers nothing".
	if got := detectCapabilities(lookPathWith("xcodebuild", "cargo")); len(got) != 0 {
		t.Fatalf("explicit empty list should win, got %v", got)
	}
}

func TestDetectsFromPathWhenNothingIsConfigured(t *testing.T) {
	unset(t, envCapabilities)
	got := detectCapabilities(lookPathWith("xcodebuild", "cargo", "go"))
	want := []string{"cargo", "go", "xcode"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	if none := detectCapabilities(lookPathWith()); len(none) != 0 {
		t.Fatalf("a bare machine offers nothing, got %v", none)
	}
}

func TestExplicitListOverridesDetection(t *testing.T) {
	t.Setenv(envCapabilities, " xcode, ,cargo ")
	got := detectCapabilities(lookPathWith("go", "node"))
	if !reflect.DeepEqual(got, []string{"xcode", "cargo"}) {
		t.Fatalf("got %v", got)
	}
}
