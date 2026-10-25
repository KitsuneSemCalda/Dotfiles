package governor

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"inferctl/internal/hardware"
	"inferctl/internal/profile"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type Lock struct{ f *os.File }

func Acquire(ctx context.Context, wait bool) (*Lock, error) {
	dir := profile.StateDir()
	if e := os.MkdirAll(dir, 0700); e != nil {
		return nil, e
	}
	f, e := os.OpenFile(filepath.Join(dir, "admission.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return nil, e
	}
	for {
		e = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if e == nil {
			return &Lock{f}, nil
		}
		if e != syscall.EWOULDBLOCK && e != syscall.EAGAIN {
			f.Close()
			return nil, e
		}
		if !wait {
			f.Close()
			return nil, errors.New("another inferctl workload owns admission; retry or use run to queue")
		}
		select {
		case <-ctx.Done():
			f.Close()
			return nil, ctx.Err()
		case <-time.After(time.Second):
		}
	}
}
func (l *Lock) Close() { _ = syscall.Flock(int(l.f.Fd()), syscall.LOCK_UN); _ = l.f.Close() }
func Admit(s hardware.Snapshot, p profile.Policy) error {
	if p.RequiredRAM == 0 {
		return errors.New("required_ram_bytes must be measured or explicitly budgeted before admission")
	}
	reserve := uint64(float64(s.Memory.Total) * p.RAMReserve / 100)
	if s.Memory.Available < reserve || p.RequiredRAM > s.Memory.Available-reserve {
		return fmt.Errorf("queued: need %d RAM bytes plus %d reserve; %d available", p.RequiredRAM, reserve, s.Memory.Available)
	}
	if p.RequiredVRAM > 0 {
		for _, g := range s.GPUs {
			if g.ID != p.GPU {
				continue
			}
			if g.VRAMTotal == nil || g.VRAMUsed == nil {
				return errors.New("dedicated VRAM unavailable; do not treat shared RAM as VRAM")
			}
			if *g.VRAMUsed > *g.VRAMTotal || p.VRAMReserve > *g.VRAMTotal-*g.VRAMUsed || p.RequiredVRAM > *g.VRAMTotal-*g.VRAMUsed-p.VRAMReserve {
				return errors.New("queued: insufficient VRAM headroom")
			}
			return nil
		}
		return errors.New("requested GPU not detected")
	}
	return nil
}
func Properties(l profile.Limits) []string {
	v := []string{fmt.Sprintf("CPUWeight=%d", l.CPUWeight), fmt.Sprintf("IOWeight=%d", l.IOWeight), fmt.Sprintf("Nice=%d", l.Nice), "MemoryAccounting=yes", "CPUAccounting=yes", "IOAccounting=yes"}
	if l.IONice != nil {
		v = append(v, "IOSchedulingClass=best-effort", fmt.Sprintf("IOSchedulingPriority=%d", *l.IONice))
	}
	if l.MemoryHigh > 0 {
		v = append(v, fmt.Sprintf("MemoryHigh=%d", l.MemoryHigh))
	}
	if l.MemoryMax > 0 {
		v = append(v, fmt.Sprintf("MemoryMax=%d", l.MemoryMax))
	}
	if l.SwapMax != nil {
		v = append(v, fmt.Sprintf("MemorySwapMax=%d", *l.SwapMax))
	}
	if l.CPUQuota > 0 {
		v = append(v, "CPUQuota="+strconv.FormatFloat(l.CPUQuota, 'f', -1, 64)+"%")
	}
	return v
}

type Unit struct {
	Name    string         `json:"name"`
	Initial profile.Limits `json:"initial"`
}

func registry(name string) string { return filepath.Join(profile.StateDir(), "units", name+".json") }
func Start(ctx context.Context, args []string, l profile.Limits) (*Unit, error) {
	if len(args) == 0 {
		return nil, errors.New("empty native command")
	}
	if e := l.Validate(); e != nil {
		return nil, e
	}
	if _, e := os.Stat("/sys/fs/cgroup/cgroup.controllers"); e != nil {
		return nil, errors.New("cgroups v2 required")
	}
	binary, e := exec.LookPath(args[0])
	if e != nil {
		return nil, e
	}
	binary, e = filepath.Abs(binary)
	if e != nil {
		return nil, e
	}
	args = append([]string{binary}, args[1:]...)
	var b [12]byte
	if _, e = rand.Read(b[:]); e != nil {
		return nil, e
	}
	u := &Unit{Name: "inferctl-" + hex.EncodeToString(b[:]) + ".service", Initial: l}
	// Journal ownership before starting so a crash cannot leave an untracked unit.
	if e = profile.Save(registry(u.Name), u); e != nil {
		return nil, e
	}
	cmd := []string{"--user", "--collect", "--service-type=exec", "--unit=" + u.Name}
	for _, p := range Properties(l) {
		cmd = append(cmd, "--property="+p)
	}
	cmd = append(cmd, "--")
	cmd = append(cmd, args...)
	out, e := exec.CommandContext(ctx, "systemd-run", cmd...).CombinedOutput()
	if e != nil {
		cleanup, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		_ = u.Stop(cleanup)
		cancel()
		return nil, fmt.Errorf("systemd-run: %w: %s (ownership retained if cleanup failed; use reset)", e, out)
	}
	return u, nil
}
func (u *Unit) Stop(ctx context.Context) error {
	out, e := exec.CommandContext(ctx, "systemctl", "--user", "stop", u.Name).CombinedOutput()
	if e != nil {
		return fmt.Errorf("stop owned unit: %w: %s", e, out)
	}
	return os.Remove(registry(u.Name))
}
func (u *Unit) Weight(ctx context.Context, w int) error {
	if w < 1 || w > 10000 {
		return errors.New("invalid CPUWeight")
	}
	if err := exec.CommandContext(ctx, "systemctl", "--user", "set-property", "--runtime", u.Name, fmt.Sprintf("CPUWeight=%d", w)).Run(); err != nil {
		return err
	}
	root, err := u.cgroupPath(ctx)
	if err != nil {
		return err
	}
	b, err := os.ReadFile(filepath.Join(root, "cpu.weight"))
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(b)) != strconv.Itoa(w) {
		return fmt.Errorf("runtime CPUWeight not applied in kernel")
	}
	return nil
}
func Reset(ctx context.Context) error {
	paths, e := filepath.Glob(filepath.Join(profile.StateDir(), "units", "*.json"))
	if e != nil {
		return e
	}
	var errs []error
	valid := regexp.MustCompile(`^inferctl-[0-9a-f]{24}\.service$`)
	for _, p := range paths {
		b, e := os.ReadFile(p)
		if e != nil {
			errs = append(errs, e)
			continue
		}
		var u Unit
		if e = json.Unmarshal(b, &u); e != nil {
			errs = append(errs, e)
			continue
		}
		if !valid.MatchString(u.Name) || filepath.Base(p) != u.Name+".json" {
			errs = append(errs, errors.New("invalid owned unit record"))
			continue
		}
		out, e := exec.CommandContext(ctx, "systemctl", "--user", "show", u.Name, "--property=LoadState", "--value").Output()
		if e != nil {
			errs = append(errs, e)
			continue
		}
		if strings.TrimSpace(string(out)) == "not-found" {
			errs = append(errs, os.Remove(p))
			continue
		}
		if e = u.Stop(ctx); e != nil {
			errs = append(errs, e)
		}
	}
	return errors.Join(errs...)
}
