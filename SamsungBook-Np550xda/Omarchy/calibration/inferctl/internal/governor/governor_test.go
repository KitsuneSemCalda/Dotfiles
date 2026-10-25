package governor

import (
	"context"
	"inferctl/internal/hardware"
	"inferctl/internal/profile"
	"strings"
	"testing"
)

func TestAdmissionPreservesReserveAndUnknownVRAM(t *testing.T) {
	h := hardware.Snapshot{Memory: hardware.Memory{Total: 1000, Available: 500}}
	p := profile.Policy{RAMReserve: 20, RequiredRAM: 301}
	if Admit(h, p) == nil {
		t.Fatal("overcommitted reserve")
	}
	p.RequiredRAM = 300
	if e := Admit(h, p); e != nil {
		t.Fatal(e)
	}
	p.RequiredVRAM = 1
	p.GPU = "card0"
	h.GPUs = []hardware.GPU{{ID: "card0"}}
	if Admit(h, p) == nil {
		t.Fatal("unknown VRAM admitted")
	}
	p.RequiredRAM = 0
	if Admit(h, p) == nil {
		t.Fatal("unknown RAM admitted")
	}
}
func TestWeightsDoNotImplyQuota(t *testing.T) {
	l := profile.Limits{CPUWeight: 80, IOWeight: 100}
	s := strings.Join(Properties(l), " ")
	if strings.Contains(s, "CPUQuota") || strings.Contains(s, "MemoryMax") {
		t.Fatal(s)
	}
}
func TestAdmissionLockSerializes(t *testing.T) {
	t.Setenv("INFERCTL_STATE", t.TempDir())
	a, e := Acquire(context.Background(), false)
	if e != nil {
		t.Fatal(e)
	}
	if b, e := Acquire(context.Background(), false); e == nil {
		b.Close()
		t.Fatal("overlapping admission")
	}
	a.Close()
	b, e := Acquire(context.Background(), false)
	if e != nil {
		t.Fatal(e)
	}
	b.Close()
}
