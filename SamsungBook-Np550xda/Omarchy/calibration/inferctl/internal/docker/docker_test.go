package docker

import (
	"inferctl/internal/profile"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPinnedImageAndPersistentMounts(t *testing.T) {
	root := t.TempDir()
	c := profile.Container{Image: "example:latest", Root: root, App: "/app", Python: "python", GPU: "cpu"}
	if _, e := Args(c, nil); e == nil {
		t.Fatal("accepted mutable image")
	}
	c.Image = "example@sha256:" + strings.Repeat("a", 64)
	for _, n := range []string{"models", "custom_nodes", "input", "output", "user", "workflows", "temp"} {
		if e := os.Mkdir(filepath.Join(root, n), 0700); e != nil {
			t.Fatal(e)
		}
	}
	a, e := Args(c, nil)
	if e != nil {
		t.Fatal(e)
	}
	s := strings.Join(a, " ")
	if strings.Count(s, "type=bind") != 7 || !strings.Contains(s, "--pull=never") || !strings.Contains(s, "127.0.0.1:8188:8188") || !strings.Contains(s, " --cpu") {
		t.Fatal(s)
	}
}

func TestLocalImageID(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"models", "custom_nodes", "input", "output", "user", "workflows", "temp"} {
		if err := os.Mkdir(filepath.Join(root, name), 0700); err != nil {
			t.Fatal(err)
		}
	}
	c := profile.Container{Image: "sha256:" + strings.Repeat("b", 64), Root: root, App: "/app/ComfyUI", Python: "python", GPU: "cpu"}
	if _, err := Args(c, nil); err != nil {
		t.Fatal(err)
	}
	for _, image := range []string{"sha256:abc", "example:fixed", "bad image@sha256:" + strings.Repeat("a", 64)} {
		c.Image = image
		if _, err := Args(c, nil); err == nil {
			t.Fatalf("accepted mutable or malformed image %q", image)
		}
	}
}
