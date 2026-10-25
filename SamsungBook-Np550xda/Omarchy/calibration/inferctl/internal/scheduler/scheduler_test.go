package scheduler

import (
	"testing"
	"time"
)

func TestHysteresisAndRecovery(t *testing.T) {
	s := New(100, 65)
	now := time.Unix(100, 0)
	if _, changed := s.Observe(now, true); changed {
		t.Fatal("changed before dwell")
	}
	if _, changed := s.Observe(now.Add(29*time.Second), true); changed {
		t.Fatal("changed early")
	}
	if w, changed := s.Observe(now.Add(30*time.Second), true); !changed || w != 65 {
		t.Fatal(w, changed)
	}
	s.Observe(now.Add(31*time.Second), false)
	s.Observe(now.Add(40*time.Second), true)
	if _, changed := s.Observe(now.Add(61*time.Second), false); changed {
		t.Fatal("transient idle recovered early")
	}
	if w, changed := s.Observe(now.Add(91*time.Second), false); !changed || w != 100 {
		t.Fatal(w, changed)
	}
}
