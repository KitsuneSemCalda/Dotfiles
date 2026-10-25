package governor

import (
	"inferctl/internal/profile"
	"os"
	"path/filepath"
	"testing"
)

func TestVerifyRejectsUnavailableOrIgnoredControls(t *testing.T) {
	root := t.TempDir()
	zero := uint64(0)
	l := profile.Limits{CPUWeight: 80, IOWeight: 100, MemoryHigh: 64 << 20, MemoryMax: 96 << 20, SwapMax: &zero}
	if _, err := verifyFiles(root, l); err == nil {
		t.Fatal("missing controllers accepted")
	}
	files := map[string]string{"cpu.weight": "80", "io.weight": "default 100", "memory.high": "67108864", "memory.max": "100663296", "memory.swap.max": "0", "cpu.max": "max 100000"}
	for k, v := range files {
		if err := os.WriteFile(filepath.Join(root, k), []byte(v), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := verifyFiles(root, l); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "cpu.weight"), []byte("100"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := verifyFiles(root, l); err == nil {
		t.Fatal("ignored CPUWeight accepted")
	}
}
func TestQuotaAndPageRoundedMemoryVerification(t *testing.T) {
	root := t.TempDir()
	l := profile.Limits{CPUWeight: 100, IOWeight: 100, MemoryHigh: 67108865, CPUQuota: 720}
	files := map[string]string{"cpu.weight": "100", "io.weight": "default 100", "memory.high": "67108864", "memory.max": "max", "memory.swap.max": "max", "cpu.max": "720000 100000"}
	for k, v := range files {
		if err := os.WriteFile(filepath.Join(root, k), []byte(v), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := verifyFiles(root, l); err != nil {
		t.Fatal(err)
	}
	l.CPUQuota = 0
	if _, err := verifyFiles(root, l); err == nil {
		t.Fatal("baseline silently capped")
	}
}

func TestMissingIOWeightAllowsOnlyTransparentNeutralFallback(t *testing.T) {
	root := t.TempDir()
	observed := map[string]string{}
	neutral := profile.Limits{IOWeight: 100}
	if err := verifyIOWeight(root, neutral, observed); err != nil {
		t.Fatal(err)
	}
	if _, exists := observed["io.weight"]; exists {
		t.Fatal("invented an applied kernel weight")
	}
	if observed["capability.io_weight"] == "" {
		t.Fatal("missing capability disclosure")
	}
	for _, weight := range []int{1, 80, 200} {
		if err := verifyIOWeight(root, profile.Limits{IOWeight: weight}, map[string]string{}); err == nil {
			t.Fatalf("silently ignored requested IOWeight=%d", weight)
		}
	}
	neutral.RequireIOWeight = true
	if err := verifyIOWeight(root, neutral, map[string]string{}); err == nil {
		t.Fatal("ignored explicit requirement for I/O controller")
	}
}
func TestExistingIOWeightMismatchDoesNotUseFallback(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "io.weight"), []byte("default 80"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := verifyIOWeight(root, profile.Limits{IOWeight: 100}, map[string]string{}); err == nil {
		t.Fatal("existing wrong default accepted")
	}
}
