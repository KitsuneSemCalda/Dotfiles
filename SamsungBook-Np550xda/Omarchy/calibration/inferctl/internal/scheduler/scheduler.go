// Package scheduler implements dwell-time hysteresis; it never changes hard memory limits.
package scheduler

import (
	"context"
	"inferctl/internal/hardware"
	"inferctl/internal/profile"
	"time"
)

type State struct {
	Weight         int
	Since          time.Time
	Pending        bool
	Dwell          time.Duration
	Base           int
	PressureWeight int
}

func New(base, pressure int) *State {
	return &State{Weight: base, Base: base, PressureWeight: pressure, Dwell: 30 * time.Second}
}
func (s *State) Observe(now time.Time, pressure bool) (int, bool) {
	target := s.Base
	if pressure {
		target = s.PressureWeight
	}
	if target == s.Weight {
		s.Since = time.Time{}
		return s.Weight, false
	}
	if s.Since.IsZero() || s.Pending != pressure {
		s.Since = now
		s.Pending = pressure
		return s.Weight, false
	}
	if now.Sub(s.Since) < s.Dwell {
		return s.Weight, false
	}
	s.Weight = target
	s.Since = time.Time{}
	return target, true
}
func Pressure(h hardware.Snapshot, p profile.Policy) bool {
	reserve := uint64(float64(h.Memory.Total) * p.RAMReserve / 100)
	if h.Memory.Available < reserve {
		return true
	}
	if t := h.MaxTemp(); t != nil && *t >= p.SoftTemp {
		return true
	}
	return false
}

// Watch only changes weights on the unit supplied by its owner. Desktop activity is not inferred from host CPU load.
func Watch(ctx context.Context, p profile.Policy, base int, apply func(context.Context, int) error, event func(string)) error {
	s := New(base, p.PressureWeight)
	tick := time.NewTicker(2 * time.Second)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case now := <-tick.C:
			h, e := hardware.SnapshotNow(ctx)
			if e != nil {
				return e
			}
			if w, changed := s.Observe(now, Pressure(h, p)); changed {
				if e = apply(ctx, w); e != nil {
					return e
				}
				event("cpu_weight_changed")
			}
		}
	}
}
