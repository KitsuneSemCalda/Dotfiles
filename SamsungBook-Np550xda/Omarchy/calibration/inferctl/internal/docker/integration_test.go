package docker

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"inferctl/internal/profile"
)

// Uses the exact local pinned ComfyUI image supplied by the operator, never a pull.
func TestDockerIntegration(t *testing.T) {
	p := os.Getenv("INFERCTL_REAL_DOCKER_PROFILE")
	if p == "" {
		t.Skip("real Docker integration requires INFERCTL_REAL_DOCKER_PROFILE")
	}
	c, err := profile.Load(p)
	if err != nil {
		t.Fatal(err)
	}
	if err = c.Validate(); err != nil {
		t.Fatal(err)
	}
	if c.Container == nil {
		t.Fatal("profile has no container")
	}
	t.Setenv("INFERCTL_STATE", t.TempDir())
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	owned, err := Create(ctx, *c.Container, c.Candidates[0].Args)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		cleanup, done := context.WithTimeout(context.Background(), 15*time.Second)
		defer done()
		_ = owned.Close(cleanup)
	}()
	raw, err := exec.CommandContext(ctx, "docker", "inspect", owned.Name).Output()
	if err != nil {
		t.Fatal(err)
	}
	var containers []struct {
		HostConfig struct {
			Memory     int64
			MemorySwap int64
			NanoCPUs   int64
		}
		Mounts []struct {
			Source      string
			Destination string
			RW          bool
		}
	}
	if err = json.Unmarshal(raw, &containers); err != nil || len(containers) != 1 {
		t.Fatal("invalid inspect", err)
	}
	actual := containers[0]
	if actual.HostConfig.Memory != int64(c.Container.Memory) || c.Container.Memory > 0 && actual.HostConfig.MemorySwap != int64(c.Container.Memory) {
		t.Fatal("memory/swap limits not applied")
	}
	if actual.HostConfig.NanoCPUs != int64(c.Container.CPUs*1e9) {
		t.Fatal("CPU quota not applied")
	}
	mounts := map[string]string{}
	for _, m := range actual.Mounts {
		mounts[m.Destination] = m.Source
	}
	for _, name := range []string{"models", "custom_nodes", "input", "output", "user", "workflows", "temp"} {
		if mounts[filepath.Join(c.Container.App, name)] != filepath.Join(c.Container.Root, name) {
			t.Fatalf("persistent %s mount missing", name)
		}
	}
	for name, source := range c.Container.ModelMounts {
		found := false
		for _, m := range actual.Mounts {
			if m.Destination == "/external/"+name && m.Source == source && !m.RW {
				found = true
			}
		}
		if !found {
			t.Fatalf("readonly external mount %s not applied", name)
		}
	}
	var nonce [12]byte
	if _, err = rand.Read(nonce[:]); err != nil {
		t.Fatal(err)
	}
	name := "inferctl-probe-" + hex.EncodeToString(nonce[:]) + ".txt"
	input := filepath.Join(c.Container.Root, "input", name)
	output := filepath.Join(c.Container.Root, "output", name)
	if err = os.WriteFile(input, nonce[:], 0600); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(input)
	defer os.Remove(output)
	script := `import pathlib,sys; import torch; app=pathlib.Path(sys.argv[1]); name=sys.argv[2]; gpu=sys.argv[3]; accelerated=(torch.xpu.is_available() if gpu=='intel' else torch.cuda.is_available()); assert gpu in ('','cpu') or accelerated, 'requested accelerator unavailable to torch'; data=(app/'input'/name).read_bytes(); f=(app/'output'/name).open('xb'); f.write(data); f.close(); print('persistent output verified; torch='+torch.__version__+'; accelerator='+str(accelerated))`
	b, err := exec.CommandContext(ctx, "docker", "exec", owned.Name, c.Container.Python, "-c", script, c.Container.App, name, c.Container.GPU).CombinedOutput()
	if err != nil {
		t.Fatalf("container probe: %v: %s", err, b)
	}
	t.Log(string(b))
	if err = owned.Close(ctx); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(output)
	if err != nil || string(got) != string(nonce[:]) {
		t.Fatal("output did not survive disposable container", err)
	}
	t.Log(fmt.Sprintf("verified image=%s memory=%d nanoCPUs=%d persistent_mounts=%d", c.Container.Image, actual.HostConfig.Memory, actual.HostConfig.NanoCPUs, len(mounts)))
}
