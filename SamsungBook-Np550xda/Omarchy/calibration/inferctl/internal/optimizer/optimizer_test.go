package optimizer

import (
	"inferctl/internal/adapters"
	"inferctl/internal/benchmark"
	"inferctl/internal/profile"
	"testing"
)

func result(name string, tps, jitter, temp float64) benchmark.Result {
	r := benchmark.Result{Candidate: profile.Candidate{Name: name}, MedianPerformance: tps, Resources: benchmark.Resources{Samples: 20, JitterP95: jitter, Temperature: &temp}}
	r.Runs = make([]adapters.Measurement, 3)
	return r
}
func TestFloorBeforeResponsiveness(t *testing.T) {
	q := profile.Default("lmstudio").Quality
	r := []benchmark.Result{result("baseline", 10, 30, 80), result("balanced", 9.8, 10, 75), result("slow", 8, 1, 60)}
	front, selected := Select(r, q, "interactive")
	if selected != "balanced" {
		t.Fatalf("selected %q front %v", selected, front)
	}
	if r[2].Eligible {
		t.Fatal("slow config passed floor")
	}
}
func TestComfyRejectsSlowerAndMoreExpensive(t *testing.T) {
	q := profile.Default("comfyui").Quality
	r := []benchmark.Result{result("A", 1.0/322, 10, 72), result("B", 1.0/279, 10, 75), result("C", 1.0/265, 10, 78), result("D", 1.0/301, 10, 80)}
	_, selected := Select(r, q, "batch")
	if selected != "C" {
		t.Fatalf("got %q", selected)
	}
}
func TestUnknownSensorAndFailureNeverWin(t *testing.T) {
	q := profile.Default("lmstudio").Quality
	r := []benchmark.Result{result("baseline", 10, 10, 70), result("failed", 11, 1, 60), result("unknown", 10.5, 1, 60)}
	r[1].Error = "OOM"
	r[2].Resources.Temperature = nil
	_, selected := Select(r, q, "batch")
	if selected != "baseline" {
		t.Fatal(selected)
	}
}
func TestUnsafeFastCandidateCannotRaiseFloor(t *testing.T) {
	q := profile.Default("lmstudio").Quality
	r := []benchmark.Result{result("baseline", 10, 10, 70), result("unsafe", 100, 1, 100)}
	_, selected := Select(r, q, "batch")
	if selected != "baseline" {
		t.Fatal("unsafe performance poisoned floor:", selected)
	}
}

func TestSpeculativeRequiresNonOverlappingGain(t *testing.T) {
	q := profile.Default("llamacpp").Quality
	r := []benchmark.Result{result("baseline", 10, 10, 70), result("draft-no-gain", 10.1, 1, 65)}
	r[0].MedianPerformanceCI = [2]float64{9.8, 10.2}
	r[1].MedianPerformanceCI = [2]float64{9.9, 10.3}
	r[1].Candidate.Speculative = true
	_, selected := Select(r, q, "batch")
	if selected != "baseline" {
		t.Fatal("accepted speculative noise", selected)
	}
	r[1].MedianPerformance = 12
	r[1].MedianPerformanceCI = [2]float64{11.5, 12.5}
	_, selected = Select(r, q, "batch")
	if selected != "draft-no-gain" {
		t.Fatal("rejected supported gain", selected)
	}
}
func TestRefinementUsesBestSafeInterval(t *testing.T) {
	c := profile.Default("lmstudio")
	r := []benchmark.Result{result("low", 10, 10, 70), result("high", 12, 10, 75), result("unsafe", 100, 10, 100)}
	for i, n := range []int{128, 512, 1024} {
		r[i].Candidate.Load = map[string]any{"eval_batch_size": n}
	}
	v := Refine(c, r)
	if len(v) != 1 || v[0].Load["eval_batch_size"] != 320 {
		t.Fatal(v)
	}
}

func TestSpeculativeOutputChangesAndHiddenOOMRejected(t *testing.T) {
	q := profile.Default("llamacpp").Quality
	r := []benchmark.Result{result("baseline", 10, 10, 70), result("draft", 12, 1, 65)}
	r[1].Candidate.Speculative = true
	r[1].MedianPerformanceCI = [2]float64{11, 13}
	r[0].MedianPerformanceCI = [2]float64{9, 10}
	r[0].Runs[0].OutputHash = "same-prompt-original-output"
	r[1].Runs[0].OutputHash = "changed-output"
	_, chosen := Select(r, q, "batch")
	if chosen != "baseline" {
		t.Fatal("quality changed", chosen)
	}
	r[1].Candidate.Speculative = false
	r[1].Resources.WorkloadCgroupPeak = map[string]uint64{"memory.events.oom_kill": 1}
	_, chosen = Select(r, q, "batch")
	if chosen != "baseline" {
		t.Fatal("OOM hidden by successful HTTP result", chosen)
	}
}
func TestUnknownVRAMCannotProveDominance(t *testing.T) {
	a, b := result("unknown", 10, 10, 70), result("known", 10, 10, 70)
	v := uint64(100)
	b.Resources.GPUVRAMPeak = &v
	if dominates(a, b, profile.Default("lmstudio").Quality) || dominates(b, a, profile.Default("lmstudio").Quality) {
		t.Fatal("unknown VRAM treated as a numeric objective")
	}
}

func TestAdditionalSwapConstraintsApplyDuringSelection(t *testing.T) {
	q := profile.Default("lmstudio").Quality
	q.SwapMode = "additional"
	r := []benchmark.Result{result("baseline", 10, 10, 70), result("excessive-traffic", 10.5, 1, 65)}
	initial := uint64(9 << 30)
	for i := range r {
		r[i].Resources.HostSwapPeak = initial
		r[i].Resources.SwapBaseline = &initial
	}
	r[1].Resources.SwapIOBytes = q.MaxSwap + 1
	_, chosen := Select(r, q, "interactive")
	if chosen != "baseline" {
		t.Fatal("accepted excessive new swap traffic", chosen)
	}
	r[1].Resources.SwapIOBytes = 0
	r[1].Resources.SwapBaseline = nil
	_, chosen = Select(r, q, "interactive")
	if chosen != "baseline" {
		t.Fatal("accepted missing swap accounting evidence", chosen)
	}
}
