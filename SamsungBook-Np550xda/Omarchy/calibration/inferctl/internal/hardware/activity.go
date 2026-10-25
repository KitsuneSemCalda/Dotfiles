package hardware

import (
	"context"
	"fmt"
	"time"
)

type DiskActivity struct {
	Name                    string   `json:"name"`
	ReadBytesPerSecond      float64  `json:"read_bytes_per_second"`
	WriteBytesPerSecond     float64  `json:"write_bytes_per_second"`
	Utilization             float64  `json:"busy_percent"`
	AverageRequestLatencyMS *float64 `json:"average_request_latency_ms,omitempty"`
	// Throughput is observed traffic, not a synthetic device capacity benchmark.
	OperationsPerSecond float64 `json:"operations_per_second"`
}
type Observation struct {
	Snapshot        Snapshot       `json:"snapshot"`
	CPUUtilization  *float64       `json:"cpu_utilization_percent,omitempty"`
	IntervalSeconds float64        `json:"interval_seconds"`
	Storage         []DiskActivity `json:"storage_activity"`
}

func Observe(ctx context.Context, interval time.Duration) (Observation, error) {
	if interval < 100*time.Millisecond || interval > 60*time.Second {
		return Observation{}, fmt.Errorf("hardware interval must be 100ms..60s")
	}
	a, e := SnapshotNow(ctx)
	if e != nil {
		return Observation{}, e
	}
	timer := time.NewTimer(interval)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return Observation{}, ctx.Err()
	case <-timer.C:
	}
	b, e := SnapshotNow(ctx)
	if e != nil {
		return Observation{}, e
	}
	seconds := b.At.Sub(a.At).Seconds()
	out := Observation{Snapshot: b, CPUUtilization: CPUUsage(a, b), IntervalSeconds: seconds}
	previous := map[string]Disk{}
	for _, d := range a.Disks {
		previous[d.Name] = d
	}
	for _, d := range b.Disks {
		p, ok := previous[d.Name]
		if !ok || d.ReadBytes < p.ReadBytes || d.WriteBytes < p.WriteBytes || d.Operations < p.Operations || d.BusyMS < p.BusyMS {
			continue
		}
		activity := DiskActivity{Name: d.Name, ReadBytesPerSecond: float64(d.ReadBytes-p.ReadBytes) / seconds, WriteBytesPerSecond: float64(d.WriteBytes-p.WriteBytes) / seconds, Utilization: float64(d.BusyMS-p.BusyMS) / seconds / 10, OperationsPerSecond: float64(d.Operations-p.Operations) / seconds}
		if d.Operations > p.Operations && d.ReadMS >= p.ReadMS && d.WriteMS >= p.WriteMS {
			latency := float64(d.ReadMS-p.ReadMS+d.WriteMS-p.WriteMS) / float64(d.Operations-p.Operations)
			activity.AverageRequestLatencyMS = &latency
		}
		out.Storage = append(out.Storage, activity)
	}
	return out, nil
}
