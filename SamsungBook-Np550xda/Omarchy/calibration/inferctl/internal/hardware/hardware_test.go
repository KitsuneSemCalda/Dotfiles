package hardware

import "testing"

func TestCounterResetIsNotCPUUsageAndSensorsRemainUnknown(t *testing.T) {
	a := Snapshot{CPU: CPU{BusyTicks: 100, TotalTicks: 200}}
	b := Snapshot{CPU: CPU{BusyTicks: 110, TotalTicks: 220}}
	u := CPUUsage(a, b)
	if u == nil || *u != 50 {
		t.Fatal(u)
	}
	if CPUUsage(b, a) != nil {
		t.Fatal("counter reset interpreted as usage")
	}
	if a.MaxTemp() != nil {
		t.Fatal("unknown sensor converted to temperature")
	}
	temp := 80.0
	a.GPUs = []GPU{{ID: "gpu", Temperature: &temp}}
	if a.MaxTemp() == nil || *a.MaxTemp() != 80 {
		t.Fatal("GPU thermal sensor omitted")
	}
}
