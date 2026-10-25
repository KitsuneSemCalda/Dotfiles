package benchmark

import (
	"context"
	"errors"
	"fmt"
	"inferctl/internal/adapters"
	"inferctl/internal/hardware"
	"inferctl/internal/profile"
	"math"
	"math/rand"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Resources struct {
	ZRAMPhysicalMemoryPeak map[string]uint64    `json:"host_zram_physical_memory_peak_bytes,omitempty"`
	SwapBaseline           *uint64              `json:"host_swap_baseline_bytes,omitempty"`
	SwapGrowthPeak         uint64               `json:"host_swap_growth_peak_bytes"`
	SwapInPages            uint64               `json:"host_swap_in_pages"`
	SwapIOBytes            uint64               `json:"host_swap_io_bytes"`
	GPUUtilizationPeak     *float64             `json:"gpu_utilization_peak_percent,omitempty"`
	CPUFrequencyMin        *float64             `json:"cpu_mean_frequency_min_mhz,omitempty"`
	CPUFrequencyMax        *float64             `json:"cpu_mean_frequency_max_mhz,omitempty"`
	GPUMinClock            *float64             `json:"gpu_clock_min_mhz,omitempty"`
	PSIAvg10Peak           map[string]float64   `json:"host_psi_avg10_peak,omitempty"`
	DiskTraffic            map[string][2]uint64 `json:"host_disk_read_write_bytes,omitempty"`

	WorkloadCgroupPeak map[string]uint64 `json:"workload_cgroup_peak,omitempty"`
	Samples            int               `json:"samples"`
	HostRAMPeak        uint64            `json:"host_ram_used_peak_bytes"`
	HostSwapPeak       uint64            `json:"host_swap_peak_bytes"`
	SwapOutPages       uint64            `json:"host_swap_out_pages"`
	Temperature        *float64          `json:"temperature_peak_c,omitempty"`
	GPUVRAMPeak        *uint64           `json:"gpu_vram_peak_bytes,omitempty"`
	CPUPeak            *float64          `json:"host_cpu_peak_percent,omitempty"`
	JitterP95          float64           `json:"scheduler_jitter_p95_ms"`
	Throttled          *bool             `json:"throttled,omitempty"`
	EnergyJoules       *float64          `json:"gpu_energy_joules,omitempty"`
}
type Result struct {
	MedianPerformanceCI [2]float64             `json:"median_performance_bootstrap_ci95"`
	Candidate           profile.Candidate      `json:"candidate"`
	Applied             map[string]any         `json:"applied"`
	Started             time.Time              `json:"started"`
	Runs                []adapters.Measurement `json:"runs"`
	Resources           Resources              `json:"resources"`
	MedianPerformance   float64                `json:"median_performance"`
	P05Performance      float64                `json:"p05_performance"`
	P95Seconds          float64                `json:"p95_seconds"`
	P95TTFT             float64                `json:"p95_ttft"`
	SustainedRatio      float64                `json:"last_half_first_half_performance_ratio"`
	Error               string                 `json:"error,omitempty"`
	Eligible            bool                   `json:"eligible"`
	Rejected            []string               `json:"rejected,omitempty"`
}
type Report struct {
	Error           string            `json:"error,omitempty"`
	Version         int               `json:"version"`
	Hardware        hardware.Snapshot `json:"hardware"`
	Config          profile.Config    `json:"config"`
	WorkloadHash    string            `json:"workload_hash"`
	Created         time.Time         `json:"created"`
	Results         []Result          `json:"results"`
	BaselineRecheck *Result           `json:"baseline_recheck,omitempty"`
	Pareto          []string          `json:"pareto"`
	Recommended     string            `json:"recommended,omitempty"`
	Validation      string            `json:"validation"`
}

func Quantile(x []float64, p float64) float64 {
	if len(x) == 0 {
		return 0
	}
	v := append([]float64(nil), x...)
	sort.Float64s(v)
	pos := float64(len(v)-1) * p
	i := int(pos)
	if i == len(v)-1 {
		return v[i]
	}
	return v[i] + (v[i+1]-v[i])*(pos-float64(i))
}
func Performance(m adapters.Measurement, backend string) float64 {
	if backend == "comfyui" {
		if m.Seconds <= 0 {
			return 0
		}
		return 1 / m.Seconds
	}
	return m.TPS
}
func Summarize(r *Result, backend string) {
	var perf, seconds, ttft []float64
	for _, m := range r.Runs {
		perf = append(perf, Performance(m, backend))
		seconds = append(seconds, m.Seconds)
		ttft = append(ttft, m.TTFT)
	}
	r.MedianPerformance = Quantile(perf, .5)
	r.MedianPerformanceCI = MedianCI(perf)
	r.P05Performance = Quantile(perf, .05)
	r.P95Seconds = Quantile(seconds, .95)
	r.P95TTFT = Quantile(ttft, .95)
	if len(perf) >= 4 {
		n := len(perf) / 2
		a := Quantile(perf[:n], .5)
		if a > 0 {
			r.SustainedRatio = Quantile(perf[len(perf)-n:], .5) / a
		}
	}
}
func Run(ctx context.Context, c profile.Config, v profile.Candidate, b adapters.Backend, event func(string), observers ...func() map[string]uint64) (r Result) {
	r = Result{Candidate: v, Started: time.Now().UTC()}
	ctx, cancel := context.WithTimeout(ctx, time.Duration(c.TimeoutSeconds*float64(time.Second)))
	defer cancel()
	// Sampling and request cancellation share a bounded lifetime. Join before reading sampler state.
	done := make(chan struct{})
	var mu sync.Mutex
	var fault error
	monitorCtx, stop := context.WithCancel(ctx)
	go func() {
		defer close(done)
		resources, e := monitor(monitorCtx, c.Quality, event, observers)
		mu.Lock()
		r.Resources = resources
		if e != nil {
			fault = e
			cancel()
		}
		mu.Unlock()
	}()
	defer func() {
		stop()
		<-done
		mu.Lock()
		defer mu.Unlock()
		if fault != nil {
			r.Error = fault.Error()
		}
		Summarize(&r, c.Backend)
	}()
	applied, e := b.Prepare(ctx, v)
	r.Applied = applied
	if e != nil {
		r.Error = e.Error()
		return
	}
	event("backend_prepared: " + v.Name)
	for i := 0; i < c.Warmup; i++ {
		if _, e = b.Run(ctx, -i-1); e != nil {
			r.Error = "warmup: " + e.Error()
			return
		}
	}
	start := time.Now()
	for i := 0; i < c.Repetitions || time.Since(start).Seconds() < c.MinSeconds; i++ {
		if i >= 1000 {
			r.Error = "1000 run safety bound reached before minimum duration"
			return
		}
		m, e := b.Run(ctx, i)
		if e != nil {
			r.Error = e.Error()
			return
		}
		if !finite(Performance(m, c.Backend)) || Performance(m, c.Backend) <= 0 || m.Seconds <= 0 {
			r.Error = "invalid backend performance metrics"
			return
		}
		r.Runs = append(r.Runs, m)
		event(fmt.Sprintf("measurement candidate=%s run=%d performance=%.4f seconds=%.3f ttft=%.3f", v.Name, i+1, Performance(m, c.Backend), m.Seconds, m.TTFT))
	}
	return
}
func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }
func monitor(ctx context.Context, q profile.Quality, event func(string), observers []func() map[string]uint64) (r Resources, err error) {
	probeCtx, stopProbe := context.WithCancel(ctx)
	probeDone := make(chan float64, 1)
	go func() { probeDone <- jitterProbe(probeCtx) }()
	defer func() { stopProbe(); r.JitterP95 = <-probeDone }()
	initial, e := hardware.SnapshotNow(ctx)
	if e != nil {
		return r, e
	}
	diskInitial := map[string]hardware.Disk{}
	for _, d := range initial.Disks {
		diskInitial[d.Name] = d
	}
	previous := initial
	swapStarted := initial.Memory.SwapUsed > 0
	var powerKnown bool
	var energy float64
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	sample := func(s hardware.Snapshot) {
		for _, device := range s.SwapDevices {
			if device.Kind != "zram" || device.PhysicalMemory == nil {
				continue
			}
			if r.ZRAMPhysicalMemoryPeak == nil {
				r.ZRAMPhysicalMemoryPeak = map[string]uint64{}
			}
			previous, ok := r.ZRAMPhysicalMemoryPeak[device.Path]
			if !ok || *device.PhysicalMemory > previous {
				r.ZRAMPhysicalMemoryPeak[device.Path] = *device.PhysicalMemory
			}
		}

		if len(s.CPU.FrequenciesMHz) > 0 {
			var sum float64
			for _, mhz := range s.CPU.FrequenciesMHz {
				sum += mhz
			}
			avg := sum / float64(len(s.CPU.FrequenciesMHz))
			if r.CPUFrequencyMin == nil || avg < *r.CPUFrequencyMin {
				x := avg
				r.CPUFrequencyMin = &x
			}
			if r.CPUFrequencyMax == nil || avg > *r.CPUFrequencyMax {
				x := avg
				r.CPUFrequencyMax = &x
			}
		}
		for resource, raw := range s.PSI {
			for _, line := range strings.Split(raw, "\n") {
				fields := strings.Fields(line)
				if len(fields) < 2 {
					continue
				}
				value := strings.TrimPrefix(fields[1], "avg10=")
				avg, err := strconv.ParseFloat(value, 64)
				if err != nil {
					continue
				}
				if r.PSIAvg10Peak == nil {
					r.PSIAvg10Peak = map[string]float64{}
				}
				key := resource + "." + fields[0]
				if avg > r.PSIAvg10Peak[key] {
					r.PSIAvg10Peak[key] = avg
				}
			}
		}
		for _, disk := range s.Disks {
			base, ok := diskInitial[disk.Name]
			if !ok || disk.ReadBytes < base.ReadBytes || disk.WriteBytes < base.WriteBytes {
				continue
			}
			if r.DiskTraffic == nil {
				r.DiskTraffic = map[string][2]uint64{}
			}
			r.DiskTraffic[disk.Name] = [2]uint64{disk.ReadBytes - base.ReadBytes, disk.WriteBytes - base.WriteBytes}
		}

		r.Samples++
		for _, observe := range observers {
			values := observe()
			if len(values) == 0 {
				continue
			}
			if r.WorkloadCgroupPeak == nil {
				r.WorkloadCgroupPeak = map[string]uint64{}
			}
			for k, n := range values {
				if n > r.WorkloadCgroupPeak[k] {
					r.WorkloadCgroupPeak[k] = n
				}
			}
		}
		used := s.Memory.Total - s.Memory.Available
		if used > r.HostRAMPeak {
			r.HostRAMPeak = used
		}
		if s.Memory.SwapUsed > r.HostSwapPeak {
			r.HostSwapPeak = s.Memory.SwapUsed
		}
		r.observeSwap(initial.Memory, s.Memory)
		if t := s.MaxTemp(); t != nil && (r.Temperature == nil || *t > *r.Temperature) {
			r.Temperature = t
		}
		if u := hardware.CPUUsage(previous, s); u != nil && (r.CPUPeak == nil || *u > *r.CPUPeak) {
			r.CPUPeak = u
		}
		for _, g := range s.GPUs {
			if g.Utilization != nil && (r.GPUUtilizationPeak == nil || *g.Utilization > *r.GPUUtilizationPeak) {
				r.GPUUtilizationPeak = g.Utilization
			}
			if g.Clock != nil && (r.GPUMinClock == nil || *g.Clock < *r.GPUMinClock) {
				r.GPUMinClock = g.Clock
			}
			if g.VRAMUsed != nil && (r.GPUVRAMPeak == nil || *g.VRAMUsed > *r.GPUVRAMPeak) {
				r.GPUVRAMPeak = g.VRAMUsed
			}
			if g.Power != nil {
				powerKnown = true
				energy += *g.Power * s.At.Sub(previous.At).Seconds()
			}
		}
		if s.CPU.ThrottleCount != nil && initial.CPU.ThrottleCount != nil {
			v := *s.CPU.ThrottleCount > *initial.CPU.ThrottleCount
			if v && (r.Throttled == nil || !*r.Throttled) {
				event("thermal_throttling_detected")
			}
			r.Throttled = &v
		}
		if !swapStarted && s.Memory.SwapUsed > 0 {
			event("swap_started")
			swapStarted = true
		}
		previous = s
	}
	sample(initial)
	if r.SwapRejected(q) {
		return r, fmt.Errorf("host swap safety threshold exceeded before warmup: mode=%q total=%d growth=%d traffic=%d limit=%d", q.SwapMode, r.HostSwapPeak, r.SwapGrowthPeak, r.SwapIOBytes, q.MaxSwap)
	}
	if t := initial.MaxTemp(); t != nil && *t >= q.HardTemp {
		return r, errors.New("hard temperature exceeded before warmup")
	}
	for {
		select {
		case <-ctx.Done():
			if powerKnown {
				r.EnergyJoules = &energy
			}
			return r, nil
		case <-ticker.C:
			s, e := hardware.SnapshotNow(ctx)
			if e != nil {
				return r, e
			}
			sample(s)
			if r.WorkloadCgroupPeak["memory.events.oom"] > 0 || r.WorkloadCgroupPeak["memory.events.oom_kill"] > 0 {
				event("workload_oom")
				return r, errors.New("workload cgroup OOM detected")
			}
			if r.SwapRejected(q) {
				message := fmt.Sprintf("host swap safety threshold exceeded: mode=%q total=%d growth=%d traffic=%d limit=%d", q.SwapMode, r.HostSwapPeak, r.SwapGrowthPeak, r.SwapIOBytes, q.MaxSwap)
				event(message)
				return r, errors.New(message)
			}
			if t := s.MaxTemp(); t != nil && *t >= q.HardTemp {
				event("thermal_hard_limit")
				return r, errors.New("hard temperature exceeded")
			}
		}
	}
}

// MedianCI is a deterministic percentile bootstrap interval; it does not remove environmental confounding.
func MedianCI(values []float64) [2]float64 {
	if len(values) < 3 {
		return [2]float64{}
	}
	rng := rand.New(rand.NewSource(42))
	medians := make([]float64, 2000)
	sample := make([]float64, len(values))
	for i := range medians {
		for j := range sample {
			sample[j] = values[rng.Intn(len(values))]
		}
		medians[i] = Quantile(sample, .5)
	}
	return [2]float64{Quantile(medians, .025), Quantile(medians, .975)}
}

func jitterProbe(ctx context.Context) float64 {
	tick := time.NewTicker(250 * time.Millisecond)
	defer tick.Stop()
	var delays []float64
	for {
		select {
		case <-ctx.Done():
			return Quantile(delays, .95)
		case due := <-tick.C:
			delays = append(delays, max(0, time.Since(due).Seconds()*1000))
		}
	}
}
