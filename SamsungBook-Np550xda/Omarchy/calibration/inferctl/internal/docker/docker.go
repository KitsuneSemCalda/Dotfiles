package docker

import (
	"errors"
	"fmt"
	"inferctl/internal/profile"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Args builds a disposable, loopback-bound container; it never pulls or edits host configuration.
func Args(c profile.Container, extra []string) ([]string, error) {
	if !regexp.MustCompile(`^(?:sha256:[0-9a-f]{64}|[^\s]+@sha256:[0-9a-f]{64})$`).MatchString(c.Image) {
		return nil, errors.New("container image must be pinned by repository digest or full local sha256 image ID")
	}
	if !filepath.IsAbs(c.Root) || !filepath.IsAbs(c.App) || c.Python == "" || strings.ContainsAny(c.Root, ",\n\r") || strings.ContainsAny(c.App, ",\n\r") {
		return nil, errors.New("absolute data_root/app_path and python executable required")
	}
	if c.CPUs < 0 {
		return nil, errors.New("cpus cannot be negative")
	}
	args := []string{"run", "--rm", "--pull=never", "--label=inferctl.managed=true", "--user=" + strconv.Itoa(os.Getuid()) + ":" + strconv.Itoa(os.Getgid()), "--publish=127.0.0.1:8188:8188", "--security-opt=no-new-privileges"}
	if c.Memory > 0 {
		args = append(args, fmt.Sprintf("--memory=%d", c.Memory), fmt.Sprintf("--memory-swap=%d", c.Memory))
	}
	if c.CPUs > 0 {
		args = append(args, "--cpus="+strconv.FormatFloat(c.CPUs, 'f', -1, 64))
	}
	switch c.GPU {
	case "nvidia":
		args = append(args, "--gpus=all")
	case "amd", "intel":
		if len(c.Devices) == 0 {
			return nil, errors.New("AMD/Intel passthrough requires explicit render devices and host permissions")
		}
	case "", "cpu":
	default:
		return nil, errors.New("gpu must be cpu, nvidia, amd or intel")
	}
	for _, g := range c.Groups {
		if _, e := strconv.ParseUint(g, 10, 32); e != nil {
			return nil, errors.New("supplementary groups must be numeric GIDs")
		}
		args = append(args, "--group-add="+g)
	}
	for _, d := range c.Devices {
		if !filepath.IsAbs(d) || !strings.HasPrefix(d, "/dev/") {
			return nil, errors.New("invalid GPU device")
		}
		args = append(args, "--device="+d)
	}
	for _, name := range []string{"models", "custom_nodes", "input", "output", "user", "workflows", "temp"} {
		host := filepath.Join(c.Root, name)
		if st, e := os.Stat(host); e != nil || !st.IsDir() {
			return nil, fmt.Errorf("create persistent directory first: %s", host)
		}
		args = append(args, "--mount=type=bind,source="+host+",target="+filepath.Join(c.App, name))
	}
	var mounts []string
	for name := range c.ModelMounts {
		mounts = append(mounts, name)
	}
	sort.Strings(mounts)
	for _, name := range mounts {
		host := c.ModelMounts[name]
		if !regexp.MustCompile(`^[a-zA-Z0-9_-]+$`).MatchString(name) || !filepath.IsAbs(host) || strings.ContainsAny(host, ",\n\r") {
			return nil, errors.New("invalid external model mount")
		}
		if st, e := os.Stat(host); e != nil || !st.IsDir() {
			return nil, fmt.Errorf("external model directory unavailable: %s", host)
		}
		args = append(args, "--mount=type=bind,source="+host+",target=/external/"+name+",readonly")
	}

	if c.ModelPaths != "" {
		if !filepath.IsAbs(c.ModelPaths) || strings.ContainsAny(c.ModelPaths, ",\n\r") {
			return nil, errors.New("invalid extra model config path")
		}
		args = append(args, "--mount=type=bind,source="+c.ModelPaths+",target=/extra_model_paths.yaml,readonly")
	}
	args = append(args, "--entrypoint="+c.Python, c.Image, filepath.Join(c.App, "main.py"), "--listen", "0.0.0.0", "--port", "8188")
	if c.GPU == "cpu" {
		args = append(args, "--cpu")
	}
	if c.ModelPaths != "" {
		args = append(args, "--extra-model-paths-config", "/extra_model_paths.yaml")
	}
	return append(args, extra...), nil
}
