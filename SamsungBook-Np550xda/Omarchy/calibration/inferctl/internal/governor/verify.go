package governor

import (
	"context"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"inferctl/internal/profile"
)

func (u *Unit) cgroupPath(ctx context.Context) (string, error) {
	b, err := exec.CommandContext(ctx, "systemctl", "--user", "show", u.Name, "--property=ControlGroup", "--value").Output()
	if err != nil {
		return "", err
	}
	relative := strings.TrimSpace(string(b))
	if relative == "" || relative == "/" || !strings.HasPrefix(relative, "/") {
		return "", fmt.Errorf("invalid workload cgroup")
	}
	root := filepath.Join("/sys/fs/cgroup", filepath.Clean(relative))
	if !strings.HasPrefix(root, "/sys/fs/cgroup/") {
		return "", fmt.Errorf("invalid workload cgroup path")
	}
	return root, nil
}

// Verify reads kernel controller files. A successful systemd D-Bus request alone
// is insufficient: a parent may have disabled or not delegated a controller.
func (u *Unit) Verify(ctx context.Context) (map[string]string, error) {
	root, err := u.cgroupPath(ctx)
	if err != nil {
		return nil, err
	}
	observed, err := verifyFiles(root, u.Initial)
	if err != nil {
		return observed, err
	}
	b, err := exec.CommandContext(ctx, "systemctl", "--user", "show", u.Name, "--property=MainPID", "--value").Output()
	if err != nil {
		return observed, err
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || pid < 1 {
		return observed, fmt.Errorf("managed process has no MainPID")
	}
	stat, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		return observed, err
	}
	fields := strings.Fields(string(stat)[strings.LastIndex(string(stat), ")")+1:])
	if len(fields) < 17 {
		return observed, fmt.Errorf("invalid managed process stat")
	}
	nice, err := strconv.Atoi(fields[16])
	if err != nil || nice != u.Initial.Nice {
		return observed, fmt.Errorf("nice not applied: got %s, expected %d", fields[16], u.Initial.Nice)
	}
	observed["process.nice"] = fields[16]
	return observed, nil
}

func verifyFiles(root string, l profile.Limits) (map[string]string, error) {
	observed := map[string]string{}
	read := func(name string) (string, error) {
		b, e := os.ReadFile(filepath.Join(root, name))
		if e != nil {
			return "", fmt.Errorf("controller %s unavailable: %w", name, e)
		}
		v := strings.TrimSpace(string(b))
		observed[name] = v
		return v, nil
	}
	check := func(name, expected string) error {
		v, e := read(name)
		if e != nil {
			return e
		}
		if v != expected {
			return fmt.Errorf("controller %s not applied: got %q, expected %q", name, v, expected)
		}
		return nil
	}
	if err := check("cpu.weight", strconv.Itoa(l.CPUWeight)); err != nil {
		return observed, err
	}
	if err := verifyIOWeight(root, l, observed); err != nil {
		return observed, err
	}

	limit := func(n uint64) string {
		if n == 0 {
			return "max"
		}
		page := uint64(os.Getpagesize())
		return strconv.FormatUint(n/page*page, 10)
	}
	for name, value := range map[string]string{"memory.high": limit(l.MemoryHigh), "memory.max": limit(l.MemoryMax)} {
		if err := check(name, value); err != nil {
			return observed, err
		}
	}
	swap := "max"
	if l.SwapMax != nil {
		page := uint64(os.Getpagesize())
		swap = strconv.FormatUint(*l.SwapMax/page*page, 10)
	}
	if err := check("memory.swap.max", swap); err != nil {
		return observed, err
	}
	quota, err := read("cpu.max")
	if err != nil {
		return observed, err
	}
	parts := strings.Fields(quota)
	if len(parts) != 2 {
		return observed, fmt.Errorf("invalid cpu.max: %q", quota)
	}
	if l.CPUQuota == 0 {
		if parts[0] != "max" {
			return observed, fmt.Errorf("unexpected CPU quota: %q", quota)
		}
	} else {
		q, e1 := strconv.ParseFloat(parts[0], 64)
		p, e2 := strconv.ParseFloat(parts[1], 64)
		if e1 != nil || e2 != nil || p <= 0 || math.Abs(q/p*100-l.CPUQuota) > .01 {
			return observed, fmt.Errorf("CPU quota mismatch: %q for %.3f%%", quota, l.CPUQuota)
		}
	}
	return observed, nil
}

// A neutral default does not request I/O prioritization. Missing io.weight must
// not prevent CPU/memory control; changed weights still require kernel evidence.
func verifyIOWeight(root string, l profile.Limits, observed map[string]string) error {
	b, err := os.ReadFile(filepath.Join(root, "io.weight"))
	if err != nil {
		if os.IsNotExist(err) && l.IOWeight == 100 && !l.RequireIOWeight {
			observed["capability.io_weight"] = "unavailable; neutral default only; I/O weighting not verified"
			return nil
		}
		return fmt.Errorf("requested IOWeight=%d cannot be verified: %w", l.IOWeight, err)
	}
	v := strings.TrimSpace(string(b))
	observed["io.weight"] = v
	for _, line := range strings.Split(v, "\n") {
		f := strings.Fields(line)
		if len(f) == 2 && f[0] == "default" && f[1] == strconv.Itoa(l.IOWeight) {
			observed["capability.io_weight"] = "verified"
			return nil
		}
	}
	return fmt.Errorf("io.weight default not applied: %q", v)
}
