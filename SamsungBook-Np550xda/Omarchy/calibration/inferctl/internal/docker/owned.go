package docker

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"inferctl/internal/profile"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

type Owned struct {
	Name  string `json:"name"`
	Image string `json:"image"`
}

func (o Owned) path() string { return filepath.Join(profile.StateDir(), "containers", o.Name+".json") }
func Create(ctx context.Context, c profile.Container, extra []string) (*Owned, error) {
	a, e := Args(c, extra)
	if e != nil {
		return nil, e
	}
	var b [12]byte
	if _, e = rand.Read(b[:]); e != nil {
		return nil, e
	}
	o := &Owned{Name: "inferctl-" + hex.EncodeToString(b[:]), Image: c.Image}
	if e = profile.Save(o.path(), o); e != nil {
		return nil, e
	}
	a[0] = "create"
	a = append(a[:1], append([]string{"--name=" + o.Name}, a[1:]...)...)
	out, e := exec.CommandContext(ctx, "docker", a...).CombinedOutput()
	if e != nil {
		cleanup, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		_ = o.Close(cleanup)
		cancel()
		return nil, fmt.Errorf("docker create: %w: %s (ownership retained if cleanup failed; use reset)", e, out)
	}
	if e = exec.CommandContext(ctx, "docker", "start", o.Name).Run(); e != nil {
		cleanup, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		_ = o.Close(cleanup)
		cancel()
		return nil, e
	}
	return o, nil
}
func (o Owned) Close(ctx context.Context) error {
	// Verify the immutable ownership label and expected image before addressing a recovered container.
	out, e := exec.CommandContext(ctx, "docker", "inspect", "--format={{json .Config}}", o.Name).Output()
	if e != nil {
		exists, lookupErr := exec.CommandContext(ctx, "docker", "container", "ls", "--all", "--filter=name=^/"+o.Name+"$", "--format={{.Names}}").Output()
		if lookupErr != nil {
			return lookupErr
		}
		if strings.TrimSpace(string(exists)) == "" {
			return os.Remove(o.path())
		}
		return e
	}
	var cfg struct {
		Image  string            `json:"Image"`
		Labels map[string]string `json:"Labels"`
	}
	if e = json.Unmarshal(out, &cfg); e != nil {
		return e
	}
	if cfg.Labels["inferctl.managed"] != "true" || cfg.Image != o.Image {
		return errors.New("container ownership mismatch; refusing stop")
	}
	if e = exec.CommandContext(ctx, "docker", "stop", "--time=10", o.Name).Run(); e != nil {
		return e
	}
	// --rm normally removes it; tolerate its disappearance, but never force-delete a running container.
	return os.Remove(o.path())
}
func Reset(ctx context.Context) error {
	paths, e := filepath.Glob(filepath.Join(profile.StateDir(), "containers", "*.json"))
	if e != nil {
		return e
	}
	valid := regexp.MustCompile(`^inferctl-[0-9a-f]{24}$`)
	var errs []error
	for _, p := range paths {
		b, e := os.ReadFile(p)
		if e != nil {
			errs = append(errs, e)
			continue
		}
		var o Owned
		if e = json.Unmarshal(b, &o); e != nil {
			errs = append(errs, e)
			continue
		}
		if !valid.MatchString(o.Name) || filepath.Base(p) != o.Name+".json" {
			errs = append(errs, errors.New("invalid container ownership record"))
			continue
		}
		if e = o.Close(ctx); e != nil {
			errs = append(errs, e)
		}
	}
	return errors.Join(errs...)
}
