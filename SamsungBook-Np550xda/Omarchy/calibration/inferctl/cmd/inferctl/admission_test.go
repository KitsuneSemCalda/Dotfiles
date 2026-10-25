package main

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestAdmissionRetriesWithoutRelaxingConstraintsOrSpammingEvents(t *testing.T) {
	calls, events := 0, 0
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	err := waitForAdmission(ctx, true, time.Millisecond, func(context.Context) error {
		calls++
		if calls < 3 {
			return errors.New("insufficient headroom")
		}
		return nil
	}, func(string) { events++ })
	if err != nil || calls != 3 || events != 1 {
		t.Fatal(calls, events, err)
	}
}
func TestAdmissionDeadlineAndFailFast(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	probe := func(context.Context) error { return errors.New("budget still unavailable") }
	if err := waitForAdmission(ctx, true, time.Hour, probe, func(string) {}); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	calls := 0
	err := waitForAdmission(context.Background(), false, time.Hour, func(context.Context) error { calls++; return errors.New("no memory") }, func(string) { t.Fatal("fail-fast should not queue") })
	if err == nil || calls != 1 {
		t.Fatal(calls, err)
	}
	canceled, stop := context.WithCancel(context.Background())
	stop()
	if err = waitForAdmission(canceled, true, time.Millisecond, func(context.Context) error { t.Fatal("probe ran after cancellation"); return nil }, func(string) {}); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
}
