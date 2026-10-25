package benchmark

import (
	"inferctl/internal/hardware"
	"inferctl/internal/profile"
	"os"
	"testing"
)

func TestOldSwapIsNotNewPressureButTrafficRemainsLimited(t *testing.T) {
	base := hardware.Memory{SwapUsed: 9 << 30, SwapInPages: 1000, SwapOutPages: 2000}
	r := Resources{HostSwapPeak: 9 << 30}
	r.observeSwap(base, base)
	q := profile.Default("lmstudio").Quality
	if !r.SwapRejected(q) {
		t.Fatal("changed legacy total accounting")
	}
	q.SwapMode = "additional"
	if r.SwapRejected(q) {
		t.Fatal("inactive old swap counted as new pressure")
	}
	current := base
	current.SwapUsed += q.MaxSwap + 1
	r.observeSwap(base, current)
	if !r.SwapRejected(q) {
		t.Fatal("new growth exceeded budget")
	}
	r = Resources{}
	current = base
	current.SwapOutPages += q.MaxSwap/uint64(os.Getpagesize()) + 1
	r.observeSwap(base, current)
	if !r.SwapRejected(q) {
		t.Fatal("swap writes hidden by constant occupancy")
	}
	r = Resources{}
	current = base
	current.SwapInPages += q.MaxSwap/uint64(os.Getpagesize()) + 1
	r.observeSwap(base, current)
	if !r.SwapRejected(q) {
		t.Fatal("swap read traffic ignored")
	}
}
func TestAdditionalAccountingNeedsEvidenceAndRejectsCounterRegression(t *testing.T) {
	q := profile.Default("lmstudio").Quality
	q.SwapMode = "additional"
	r := Resources{}
	if !r.SwapRejected(q) {
		t.Fatal("old report with no counters accepted")
	}
	base := hardware.Memory{SwapInPages: 100}
	r.observeSwap(base, hardware.Memory{SwapInPages: 99})
	if !r.SwapRejected(q) {
		t.Fatal("counter regression accepted")
	}
	r.observeSwap(base, base)
	if !r.SwapRejected(q) {
		t.Fatal("later observation erased invalid counters")
	}
}
