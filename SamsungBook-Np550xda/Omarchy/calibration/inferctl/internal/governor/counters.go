package governor

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Observer reads only the cgroup belonging to this newly created transient unit.
func (u *Unit) Observer(ctx context.Context) (func() map[string]uint64, error) {
	root, e := u.cgroupPath(ctx)
	if e != nil {
		return nil, e
	}
	if _, e = os.ReadFile(filepath.Join(root, "memory.current")); e != nil {
		return nil, fmt.Errorf("workload memory controller unavailable: %w", e)
	}

	return func() map[string]uint64 {
		out := map[string]uint64{}
		for _, name := range []string{"memory.current", "memory.peak", "memory.swap.current"} {
			b, e := os.ReadFile(filepath.Join(root, name))
			if e != nil {
				continue
			}
			n, e := strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
			if e == nil {
				out[name] = n
			}
		}
		for _, name := range []string{"memory.events", "memory.stat", "cpu.stat"} {
			b, e := os.ReadFile(filepath.Join(root, name))
			if e != nil {
				continue
			}
			for _, line := range strings.Split(string(b), "\n") {
				v := strings.Fields(line)
				if len(v) != 2 {
					continue
				}
				switch v[0] {
				case "oom", "oom_kill", "pgfault", "pgmajfault", "anon", "file", "usage_usec", "user_usec", "system_usec", "nr_throttled", "throttled_usec":
					n, e := strconv.ParseUint(v[1], 10, 64)
					if e == nil {
						out[name+"."+v[0]] = n
					}
				}
			}
		}
		b, e := os.ReadFile(filepath.Join(root, "io.stat"))
		if e == nil {
			for _, line := range strings.Split(string(b), "\n") {
				for _, f := range strings.Fields(line) {
					k, v, ok := strings.Cut(f, "=")
					if !ok {
						continue
					}
					n, e := strconv.ParseUint(v, 10, 64)
					if e == nil {
						out["io.stat."+k] += n
					}
				}
			}
		}
		return out
	}, nil
}
