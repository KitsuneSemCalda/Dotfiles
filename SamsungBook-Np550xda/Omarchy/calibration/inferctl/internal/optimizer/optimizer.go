package optimizer

import (
	"inferctl/internal/benchmark"
	"inferctl/internal/profile"
	"math"
	"sort"
)

// Select uses hard constraints first, then exact nondominance and explicit mode-specific ordering.
// For n <= 64 candidates and d <= 7 objectives, O(n²d) is bounded and simpler than an index.
func Select(results []benchmark.Result, q profile.Quality, mode string) ([]string, string) {
	if len(results) == 0 {
		return nil, ""
	}
	baseline := results[0].MedianPerformance
	for i := range results {
		r := &results[i]
		r.Rejected = nil
		reject := func(s string) { r.Rejected = append(r.Rejected, s) }
		if r.Candidate.Speculative {
			for j, m := range r.Runs {
				if j >= len(results[0].Runs) {
					break
				}
				base := results[0].Runs[j]
				if m.OutputHash != "" && base.OutputHash != "" && m.OutputHash != base.OutputHash {
					reject("speculative decoding changed deterministic output")
					break
				}
			}
		}
		if r.Candidate.Speculative && (r.MedianPerformanceCI[0] <= results[0].MedianPerformanceCI[1] || r.MedianPerformanceCI[0] <= baseline) {
			reject("speculative decoding lacks reproducible performance gain over baseline")
		}
		if r.Resources.WorkloadCgroupPeak["memory.events.oom"] > 0 || r.Resources.WorkloadCgroupPeak["memory.events.oom_kill"] > 0 {
			reject("workload OOM")
		}
		if r.Error != "" {
			reject(r.Error)
		}
		if len(r.Runs) < 3 {
			reject("insufficient repetitions")
		}
		if r.P95TTFT > q.MaxTTFT {
			reject("TTFT")
		}
		if r.Resources.SwapRejected(q) {
			reject("swap")
		}
		if r.Resources.Temperature == nil {
			reject("temperature sensor unavailable")
		} else if *r.Resources.Temperature >= q.HardTemp {
			reject("temperature")
		}
		if mode == "interactive" && r.Resources.JitterP95 > q.MaxJitter {
			reject("scheduler latency")
		}
		if r.Resources.Samples < 2 {
			reject("insufficient resource samples")
		}
		r.Eligible = len(r.Rejected) == 0
	}
	best := baseline
	for _, r := range results {
		if r.Eligible && r.MedianPerformance > best {
			best = r.MedianPerformance
		}
	}
	for i := range results {
		r := &results[i]
		if baseline <= 0 || r.MedianPerformance < baseline*q.MinRatio || r.MedianPerformance < best*q.MinRatio {
			r.Rejected = append(r.Rejected, "performance floor")
			r.Eligible = false
		}
	}
	var front []int
	for i := range results {
		if !results[i].Eligible {
			continue
		}
		dominated := false
		for j := range results {
			if i != j && results[j].Eligible && dominates(results[j], results[i], q) {
				dominated = true
				break
			}
		}
		if !dominated {
			front = append(front, i)
		}
	}
	sort.SliceStable(front, func(i, j int) bool {
		a, b := results[front[i]], results[front[j]]
		if mode == "interactive" {
			if a.Resources.JitterP95 != b.Resources.JitterP95 {
				return a.Resources.JitterP95 < b.Resources.JitterP95
			}
			if *a.Resources.Temperature != *b.Resources.Temperature {
				return *a.Resources.Temperature < *b.Resources.Temperature
			}
		}
		return a.MedianPerformance > b.MedianPerformance
	})
	names := []string{}
	for _, i := range front {
		names = append(names, results[i].Candidate.Name)
	}
	if len(names) == 0 {
		return names, ""
	}
	return names, names[0]
}
func objectives(r benchmark.Result, q profile.Quality) []float64 {
	vram, energy := math.Inf(1), math.Inf(1)
	if r.Resources.GPUVRAMPeak != nil {
		vram = float64(*r.Resources.GPUVRAMPeak)
	}
	if r.Resources.EnergyJoules != nil {
		energy = *r.Resources.EnergyJoules / float64(max(1, len(r.Runs)))
	}
	return []float64{-r.MedianPerformance, float64(r.Resources.HostRAMPeak), vram, float64(r.Resources.SwapObjective(q)), *r.Resources.Temperature, r.Resources.JitterP95, energy}
}
func dominates(a, b benchmark.Result, q profile.Quality) bool {
	if (a.Resources.GPUVRAMPeak == nil) != (b.Resources.GPUVRAMPeak == nil) || (a.Resources.EnergyJoules == nil) != (b.Resources.EnergyJoules == nil) {
		return false
	}
	av, bv := objectives(a, q), objectives(b, q)
	strict := false
	for i := range av {
		if av[i] > bv[i] {
			return false
		}
		if av[i] < bv[i] {
			strict = true
		}
	}
	return strict
}
