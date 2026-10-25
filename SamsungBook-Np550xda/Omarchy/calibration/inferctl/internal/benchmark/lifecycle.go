package benchmark

import (
	"context"
	"errors"
	"fmt"
	"inferctl/internal/docker"
	"inferctl/internal/governor"
	"inferctl/internal/profile"
	"inferctl/internal/scheduler"
	"net"
	"net/http"
	"net/url"
	"os"

	"time"
)

type Lifecycle struct {
	Verified  map[string]string
	Unit      *governor.Unit
	Container *docker.Owned
	cancel    context.CancelFunc
	watch     chan error
}

func Start(ctx context.Context, c profile.Config, v profile.Candidate, dynamic bool, event func(string)) (*Lifecycle, error) {
	l := &Lifecycle{}
	if len(c.Command) > 0 || c.Container != nil {
		endpoint, err := url.Parse(c.URL)
		if err != nil {
			return nil, err
		}
		conn, err := net.DialTimeout("tcp", endpoint.Host, 300*time.Millisecond)
		if err == nil {
			conn.Close()
			return nil, errors.New("managed backend port already occupied; refusing to benchmark another process")
		}
	}
	if c.Container != nil {

		o, e := docker.Create(ctx, *c.Container, v.Args)
		if e != nil {
			return nil, e
		}
		l.Container = o
	} else if len(c.Command) > 0 {
		args := append(append([]string(nil), c.Command...), v.Args...)
		u, e := governor.Start(ctx, args, v.Limits)
		if e != nil {
			return nil, e
		}
		l.Unit = u
		verified, err := u.Verify(ctx)
		if err != nil {
			cleanupErr := l.Close()
			return nil, errors.Join(fmt.Errorf("resource controls not verified: %w", err), cleanupErr)
		}
		l.Verified = verified
	} else {
		if len(v.Args) > 0 {
			return nil, errors.New("candidate args require a managed command or container")
		}
		base := profile.Limits{CPUWeight: 100, IOWeight: 100}
		if profile.Hash(v.Limits) != profile.Hash(base) {
			return nil, errors.New("resource changes require managed command; external server cannot be governed safely")
		}
		if dynamic {
			return nil, errors.New("dynamic scheduling requires managed native command")
		}
		return l, nil
	}
	if dynamic {
		if l.Unit == nil {
			_ = l.Close()
			return nil, errors.New("dynamic scheduling currently supports native systemd units")
		}
		watchCtx, cancel := context.WithCancel(ctx)
		l.cancel = cancel
		l.watch = make(chan error, 1)
		go func() { l.watch <- scheduler.Watch(watchCtx, c.Policy, v.Limits.CPUWeight, l.Unit.Weight, event) }()
	}
	readyCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	client := &http.Client{Timeout: time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	path := "/health"
	if c.Backend == "lmstudio" {
		path = "/api/v1/models"
	}
	if c.Backend == "comfyui" {
		path = "/system_stats"
	}
	for {
		req, e := http.NewRequestWithContext(readyCtx, "GET", c.URL+path, nil)
		if e != nil {
			_ = l.Close()
			return nil, e
		}
		if token := os.Getenv("INFERCTL_API_TOKEN"); token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		resp, e := client.Do(req)
		if e == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				return l, nil
			}
		}
		select {
		case <-readyCtx.Done():
			_ = l.Close()
			return nil, fmt.Errorf("backend readiness: %w", readyCtx.Err())
		case <-time.After(250 * time.Millisecond):
		}
	}
}
func (l *Lifecycle) Close() error {
	var errs []error
	if l.cancel != nil {
		l.cancel()
		if e := <-l.watch; e != nil {
			errs = append(errs, e)
		}
		l.cancel = nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if l.Container != nil {
		if e := l.Container.Close(ctx); e != nil {
			errs = append(errs, e)
		}
		l.Container = nil
	}
	if l.Unit != nil {
		if e := l.Unit.Stop(ctx); e != nil {
			errs = append(errs, e)
		}
		l.Unit = nil
	}
	return errors.Join(errs...)
}
