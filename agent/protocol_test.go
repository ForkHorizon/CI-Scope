package agent

import (
	"encoding/json"
	"testing"
)

func TestCanonicalJSONSortsNestedStructKeys(t *testing.T) {
	type nested struct {
		Z string `json:"z"`
		A string `json:"a"`
	}
	value := struct {
		Reservation nested `json:"reservation"`
		Type        string `json:"type"`
	}{
		Reservation: nested{Z: "last", A: "first"},
		Type:        "scheduler.reconcile",
	}

	canonical, err := CanonicalJSON(value)
	if err != nil {
		t.Fatal(err)
	}
	const want = `{"reservation":{"a":"first","z":"last"},"type":"scheduler.reconcile"}`
	if string(canonical) != want {
		t.Fatalf("canonical=%s want=%s", canonical, want)
	}

	var decoded any
	if err := json.Unmarshal(canonical, &decoded); err != nil {
		t.Fatal(err)
	}
}
