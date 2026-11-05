package agent

import "testing"

func TestParseSystemProfilerKeepsOnlyHarmlessFields(t *testing.T) {
	data := []byte(`{"SPHardwareDataType":[{"machine_name":"MacBook Pro","machine_model":"MacBookPro18,3","chip_type":"Apple M1 Pro","serial_number":"SECRET","platform_UUID":"SECRET","physical_memory":"16 GB"}]}`)
	got := parseSystemProfiler(data)
	want := HardwareFacts{ModelName: "MacBook Pro", ModelID: "MacBookPro18,3", Chip: "Apple M1 Pro"}
	if got != want {
		t.Fatalf("got %+v, want %+v", got, want)
	}
	if intel := parseSystemProfiler([]byte(`{"SPHardwareDataType":[{"machine_name":"iMac","cpu_type":"Quad-Core Intel Core i5"}]}`)); intel.Chip != "Quad-Core Intel Core i5" {
		t.Fatalf("Intel chip not read: %+v", intel)
	}
	if empty := parseSystemProfiler([]byte(`not json`)); empty != (HardwareFacts{}) {
		t.Fatalf("garbage should give nothing, got %+v", empty)
	}
	if macOSName("15.2") != "macOS 15.2" || macOSName("") != "" || macOSName("abc") != "" {
		t.Fatal("macOSName")
	}
}
