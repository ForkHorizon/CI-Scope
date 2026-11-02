// Test helper for clearing an environment variable for one test.
package main

import (
	"os"
	"testing"
)

func unset(t *testing.T, name string) {
	t.Helper()
	previous, had := os.LookupEnv(name)
	if err := os.Unsetenv(name); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if had {
			_ = os.Setenv(name, previous)
		}
	})
}
