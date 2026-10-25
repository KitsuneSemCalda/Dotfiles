package profile

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
)

type Limits struct {
	RequireIOWeight bool    `json:"require_io_weight,omitempty"`
	IONice          *int    `json:"io_nice_priority,omitempty"`
	CPUWeight       int     `json:"cpu_weight"`
	IOWeight        int     `json:"io_weight"`
	CPUQuota        float64 `json:"cpu_quota_percent,omitempty"`
	MemoryHigh      uint64  `json:"memory_high_bytes,omitempty"`
	MemoryMax       uint64  `json:"memory_max_bytes,omitempty"`
	SwapMax         *uint64 `json:"swap_max_bytes,omitempty"`
	Nice            int     `json:"nice"`
}
type Quality struct {
	SwapMode      string  `json:"swap_accounting,omitempty"`
	MinRatio      float64 `json:"min_performance_ratio"`
	MaxTTFT       float64 `json:"max_ttft_seconds"`
	MaxSwap       uint64  `json:"max_host_swap_bytes"`
	HardTemp      float64 `json:"hard_temperature_c"`
	MaxJitter     float64 `json:"max_scheduler_jitter_ms"`
	BaselineDrift float64 `json:"max_baseline_drift_ratio"`
}
type Policy struct {
	PressureWeight int     `json:"pressure_cpu_weight,omitempty"`
	Mode           string  `json:"mode"`
	CPUReserve     float64 `json:"cpu_reserve_percent"`
	RAMReserve     float64 `json:"ram_reserve_percent"`
	VRAMReserve    uint64  `json:"vram_reserve_bytes"`
	RequiredRAM    uint64  `json:"required_ram_bytes"`
	RequiredVRAM   uint64  `json:"required_vram_bytes"`
	GPU            string  `json:"gpu_id,omitempty"`
	Exclusive      bool    `json:"exclusive"`
	SoftTemp       float64 `json:"soft_temperature_c"`
}
type Candidate struct {
	Speculative bool           `json:"speculative,omitempty"`
	Name        string         `json:"name"`
	Load        map[string]any `json:"load,omitempty"`
	Args        []string       `json:"args,omitempty"`
	Limits      Limits         `json:"limits"`
}
type Container struct {
	Image       string            `json:"image"`
	Root        string            `json:"data_root"`
	App         string            `json:"app_path"`
	Python      string            `json:"python"`
	GPU         string            `json:"gpu"`
	ModelPaths  string            `json:"extra_model_paths_config,omitempty"`
	CPUs        float64           `json:"cpus,omitempty"`
	Memory      uint64            `json:"memory_bytes,omitempty"`
	Devices     []string          `json:"devices,omitempty"`
	Groups      []string          `json:"supplementary_groups,omitempty"`
	ModelMounts map[string]string `json:"model_mounts,omitempty"`
}
type Resident struct {
	Backend  string `json:"backend"`
	URL      string `json:"url"`
	Model    string `json:"model"`
	Instance string `json:"instance_id"`
}
type Config struct {
	HardwareID     string      `json:"hardware_id,omitempty"`
	ModelRevision  string      `json:"model_revision,omitempty"`
	Release        []Resident  `json:"release_before,omitempty"`
	Version        int         `json:"version"`
	Backend        string      `json:"backend"`
	URL            string      `json:"url"`
	Model          string      `json:"model"`
	Workload       string      `json:"workload"`
	Prompt         string      `json:"prompt"`
	ImagesPerRun   int         `json:"images_per_run,omitempty"`
	FramesPerRun   int         `json:"frames_per_run,omitempty"`
	Workflow       string      `json:"workflow,omitempty"`
	SeedNodes      []string    `json:"seed_nodes,omitempty"`
	Seed           int64       `json:"seed"`
	Tokens         int         `json:"tokens"`
	Repetitions    int         `json:"repetitions"`
	Warmup         int         `json:"warmup"`
	MinSeconds     float64     `json:"min_seconds"`
	TimeoutSeconds float64     `json:"timeout_seconds"`
	Policy         Policy      `json:"policy"`
	Quality        Quality     `json:"quality"`
	Candidates     []Candidate `json:"candidates"`
	Command        []string    `json:"command,omitempty"`
	Container      *Container  `json:"container,omitempty"`
}

func Default(backend string) Config {
	u := "http://127.0.0.1:1234"
	if backend == "comfyui" {
		u = "http://127.0.0.1:8188"
	}
	if backend == "llamacpp" {
		u = "http://127.0.0.1:8080"
	}
	c := Config{Version: 1, Backend: backend, URL: u, Workload: "default", Prompt: "Explain how virtual memory works, in detail, with examples.", Seed: 42, Tokens: 256, Repetitions: 3, Warmup: 1, MinSeconds: 120, TimeoutSeconds: 1800, Policy: Policy{Mode: "interactive", CPUReserve: 15, RAMReserve: 20, SoftTemp: 82}, Quality: Quality{MinRatio: .9, MaxTTFT: 30, MaxSwap: 256 << 20, HardTemp: 92, MaxJitter: 50, BaselineDrift: .1}, Candidates: []Candidate{{Name: "baseline", Limits: Limits{CPUWeight: 100, IOWeight: 100}}}}
	if backend == "lmstudio" {
		c.Candidates[0].Load = map[string]any{"context_length": 4096}
	}
	return c
}
func (c Config) Validate() error {
	if c.Quality.SwapMode != "" && c.Quality.SwapMode != "total" && c.Quality.SwapMode != "additional" {
		return errors.New("swap_accounting must be total or additional")
	}
	if len(c.Release) > 0 && !c.Policy.Exclusive {
		return errors.New("release_before requires exclusive policy")
	}
	for _, r := range c.Release {
		if r.Backend != "lmstudio" || r.Instance == "" || r.Model == "" || r.URL == "" {
			return errors.New("release_before requires exact LM Studio resident identity")
		}
	}
	if c.ImagesPerRun < 0 || c.FramesPerRun < 0 {
		return errors.New("negative workflow output count")
	}
	if c.Version != 1 {
		return errors.New("unsupported profile version")
	}
	if c.Backend != "lmstudio" && c.Backend != "llamacpp" && c.Backend != "comfyui" {
		return errors.New("backend must be lmstudio, llamacpp or comfyui")
	}
	if c.Policy.Mode != "interactive" && c.Policy.Mode != "batch" && c.Policy.Mode != "idle" && c.Policy.Mode != "night" {
		return errors.New("invalid mode")
	}
	if c.Quality.MinRatio <= 0 || c.Quality.MinRatio > 1 || c.Quality.BaselineDrift <= 0 || c.Quality.BaselineDrift >= 1 || c.Quality.HardTemp <= c.Policy.SoftTemp || c.Policy.SoftTemp <= 0 || c.Quality.MaxTTFT <= 0 || c.Quality.MaxJitter <= 0 {
		return errors.New("invalid quality or thermal constraints")
	}
	if c.Policy.PressureWeight < 0 || c.Policy.PressureWeight > 10000 {
		return errors.New("invalid pressure CPUWeight")
	}
	if c.Policy.CPUReserve < 0 || c.Policy.CPUReserve >= 100 {
		return errors.New("cpu_reserve_percent must be 0..<100")
	}
	if c.Policy.RAMReserve < 0 || c.Policy.RAMReserve >= 100 || c.Repetitions < 3 || c.Repetitions > 100 || c.Warmup < 1 || c.MinSeconds < 0 || c.TimeoutSeconds <= c.MinSeconds || c.TimeoutSeconds > 86400 || c.Tokens < 2 || c.Tokens > 1048576 || c.Workload == "" {
		return errors.New("invalid benchmark bounds (at least 3 repetitions and 1 warm-up)")
	}
	if c.Policy.RequiredVRAM > 0 && c.Policy.GPU == "" {
		return errors.New("gpu_id required for VRAM admission")
	}
	if len(c.Candidates) == 0 || len(c.Candidates) > 64 {
		return errors.New("expected 1..64 candidates")
	}
	names := map[string]bool{}
	for _, v := range c.Candidates {
		if v.Name == "" || names[v.Name] {
			return errors.New("candidate names must be unique and nonempty")
		}
		names[v.Name] = true
		if err := v.Limits.Validate(); err != nil {
			return err
		}
	}
	if c.Backend == "comfyui" && (c.Workflow == "" || len(c.SeedNodes) == 0) {
		return errors.New("ComfyUI requires API workflow and explicit seed_nodes")
	}
	if c.Backend != "comfyui" && c.Model == "" {
		return errors.New("model required")
	}
	if c.Container != nil && (c.Backend != "comfyui" || len(c.Command) > 0) {
		return errors.New("container is exclusive with command and requires comfyui")
	}
	return nil
}
func (l Limits) Validate() error {
	if l.IONice != nil && (*l.IONice < 0 || *l.IONice > 7) {
		return errors.New("io_nice_priority must be 0..7")
	}
	if l.CPUWeight < 1 || l.CPUWeight > 10000 || l.IOWeight < 1 || l.IOWeight > 10000 || l.CPUQuota < 0 || l.Nice < 0 || l.Nice > 19 {
		return errors.New("invalid resource limits (nice must be 0..19 without privilege)")
	}
	if l.MemoryMax > 0 && l.MemoryHigh > l.MemoryMax {
		return errors.New("MemoryHigh exceeds MemoryMax")
	}
	return nil
}
func Load(path string) (Config, error) {
	c := Config{}
	f, e := os.Open(path)
	if e != nil {
		return c, e
	}
	defer f.Close()
	d := json.NewDecoder(io.LimitReader(f, 4<<20))
	d.DisallowUnknownFields()
	if e = d.Decode(&c); e != nil {
		return c, e
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		return c, errors.New("trailing profile data")
	}
	return c, nil
}
func Hash(v any) string {
	b, _ := json.Marshal(v)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}
func StateDir() string {
	if s := os.Getenv("INFERCTL_STATE"); s != "" {
		return s
	}
	s := os.Getenv("XDG_STATE_HOME")
	if s == "" {
		h, _ := os.UserHomeDir()
		s = filepath.Join(h, ".local/state")
	}
	return filepath.Join(s, "inferctl")
}
func Save(path string, v any) error {
	if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		return e
	}
	b, e := json.MarshalIndent(v, "", "  ")
	if e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(path), ".inferctl-*")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	if _, e = f.Write(append(b, '\n')); e != nil {
		f.Close()
		return e
	}
	if e = f.Sync(); e != nil {
		f.Close()
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	return os.Rename(f.Name(), path)
}
