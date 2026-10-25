package main

import (
	"context"
	"fmt"
	"time"
)

// Waiting retries the original constraints; it never changes the requested budget.
func waitForAdmission(ctx context.Context, retry bool, interval time.Duration, probe func(context.Context) error, event func(string)) error {
	var last error
	queued := false
	for {
		if err := ctx.Err(); err != nil {
			return fmt.Errorf("admission wait ended: %w; last check: %v", err, last)
		}
		last = probe(ctx)
		if last == nil {
			return nil
		}
		if !retry {
			return last
		}
		if !queued {
			event("admission_queued: " + last.Error())
			queued = true
		}
		timer := time.NewTimer(interval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return fmt.Errorf("admission wait ended: %w; last check: %v", ctx.Err(), last)
		case <-timer.C:
		}
	}
}
