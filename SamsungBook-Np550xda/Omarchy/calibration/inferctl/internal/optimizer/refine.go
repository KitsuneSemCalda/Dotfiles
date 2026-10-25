package optimizer

import (
	"fmt"
	"inferctl/internal/benchmark"
	"inferctl/internal/profile"
	"sort"
	"strconv"
)

// Refine bisects the measured interval around the best safe point, at most twice.
// This is a bounded local search, not a claim of global optimality or monotonic performance.
func Refine(c profile.Config, results []benchmark.Result) []profile.Candidate {
	key, flag := "", ""
	switch c.Backend {
	case "lmstudio":
		key = "eval_batch_size"
	case "llamacpp":
		flag = "--threads"
	default:
		return nil
	}
	type point struct {
		n int
		r benchmark.Result
	}
	var points []point
	for _, r := range results {
		if r.Error != "" || r.Resources.Temperature == nil || *r.Resources.Temperature >= c.Quality.HardTemp || r.Resources.SwapRejected(c.Quality) {
			continue
		}
		n := 0
		if key != "" {
			if v, ok := r.Candidate.Load[key]; ok {
				n, _ = strconv.Atoi(fmt.Sprint(v))
			}
		} else {
			for i := 0; i+1 < len(r.Candidate.Args); i++ {
				if r.Candidate.Args[i] == flag {
					n, _ = strconv.Atoi(r.Candidate.Args[i+1])
				}
			}
		}
		if n > 0 {
			points = append(points, point{n, r})
		}
	}
	if len(points) < 2 {
		return nil
	}
	sort.Slice(points, func(i, j int) bool { return points[i].n < points[j].n })
	best := 0
	for i := range points {
		if points[i].r.MedianPerformance > points[best].r.MedianPerformance {
			best = i
		}
	}
	var candidates []profile.Candidate
	for _, i := range []int{best - 1, best + 1} {
		if i < 0 || i >= len(points) {
			continue
		}
		a, b := points[i].n, points[best].n
		mid := (a + b) / 2
		if mid == a || mid == b {
			continue
		}
		v := points[best].r.Candidate
		v.Name = fmt.Sprintf("refine-%s%d", c.Backend, mid)
		if key != "" {
			v.Load = map[string]any{}
			for k, x := range points[best].r.Candidate.Load {
				v.Load[k] = x
			}
			v.Load[key] = mid
		} else {
			v.Args = append([]string(nil), v.Args...)
			for j := 0; j+1 < len(v.Args); j++ {
				if v.Args[j] == flag {
					v.Args[j+1] = strconv.Itoa(mid)
				}
			}
		}
		candidates = append(candidates, v)
	}
	return candidates
}
