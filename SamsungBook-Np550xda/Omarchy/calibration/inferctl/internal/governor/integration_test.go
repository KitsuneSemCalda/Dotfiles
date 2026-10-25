package governor

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"inferctl/internal/profile"
)

// Explicit opt-in: this starts only a short-lived sleep in a transient user unit.
// It does not allocate large memory, trigger OOM, or change desktop/system configuration.
func TestSystemdIntegration(t *testing.T) {
	if os.Getenv("INFERCTL_REAL_SYSTEMD") != "1" {
		t.Skip("real systemd integration requires INFERCTL_REAL_SYSTEMD=1")
	}
	t.Setenv("INFERCTL_STATE", t.TempDir())
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	zero := uint64(0)
	limits := profile.Limits{CPUWeight: 80, IOWeight: 100, MemoryHigh: 64 << 20, MemoryMax: 96 << 20, SwapMax: &zero, Nice: 2}
	u, err := Start(ctx, []string{"sleep", "120"}, limits)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		cleanup, done := context.WithTimeout(context.Background(), 10*time.Second)
		defer done()
		_ = u.Stop(cleanup)
	}()
	verified, err := u.Verify(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("verified kernel controllers: %v", verified)
	observe, err := u.Observer(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := observe()["memory.current"]; !ok {
		t.Fatal("missing actual cgroup memory counter")
	}
	if err = u.Weight(ctx, 65); err != nil {
		t.Fatal(err)
	}
	root, err := u.cgroupPath(ctx)
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(root, "cpu.weight"))
	if err != nil || strings.TrimSpace(string(b)) != "65" {
		t.Fatalf("weight not changed in kernel: %s %v", b, err)
	}
	if err = Reset(ctx); err != nil {
		t.Fatal(err)
	}
	active, _ := exec.CommandContext(ctx, "systemctl", "--user", "is-active", u.Name).Output()
	if strings.TrimSpace(string(active)) == "active" {
		t.Fatal("reset left owned unit active")
	}
	if _, err = os.Stat(registry(u.Name)); !os.IsNotExist(err) {
		t.Fatal("ownership record survived reset", err)
	}
}
