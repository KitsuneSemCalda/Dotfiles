package benchmark

import (
	"inferctl/internal/hardware"
	"inferctl/internal/profile"
	"os"
)

func (r *Resources) observeSwap(base, current hardware.Memory) {
	if r.SwapBaseline == nil {
		n := base.SwapUsed
		r.SwapBaseline = &n
	}
	if current.SwapUsed > base.SwapUsed {
		growth := current.SwapUsed - base.SwapUsed
		if growth > r.SwapGrowthPeak {
			r.SwapGrowthPeak = growth
		}
	}
	// Counter regression invalidates the additional accounting evidence instead of
	// reporting zero traffic. Saturation also prevents byte-count overflow.
	if current.SwapInPages < base.SwapInPages || current.SwapOutPages < base.SwapOutPages {
		r.SwapIOBytes = ^uint64(0)
		return
	}
	r.SwapInPages = current.SwapInPages - base.SwapInPages
	r.SwapOutPages = current.SwapOutPages - base.SwapOutPages
	maximum := ^uint64(0)
	page := uint64(os.Getpagesize())
	if r.SwapInPages > maximum-r.SwapOutPages || r.SwapInPages+r.SwapOutPages > maximum/page {
		r.SwapIOBytes = maximum
		return
	}
	traffic := (r.SwapInPages + r.SwapOutPages) * page
	if traffic > r.SwapIOBytes {
		r.SwapIOBytes = traffic
	}
}
func (r Resources) SwapRejected(q profile.Quality) bool {
	if q.SwapMode == "additional" {
		return r.SwapBaseline == nil || r.SwapIOBytes == ^uint64(0) || r.SwapGrowthPeak > q.MaxSwap || r.SwapIOBytes > q.MaxSwap
	}
	return r.HostSwapPeak > q.MaxSwap
}
func (r Resources) SwapObjective(q profile.Quality) uint64 {
	if q.SwapMode == "additional" {
		return max(r.SwapGrowthPeak, r.SwapIOBytes)
	}
	return r.HostSwapPeak
}
