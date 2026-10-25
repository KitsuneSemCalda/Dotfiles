package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"inferctl/internal/adapters"
	"inferctl/internal/benchmark"
	"inferctl/internal/docker"
	"inferctl/internal/governor"
	"inferctl/internal/hardware"
	"inferctl/internal/optimizer"
	"inferctl/internal/profile"
	"math"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if e := run(ctx, os.Args[1:]); e != nil {
		fmt.Fprintln(os.Stderr, "inferctl:", e)
		os.Exit(1)
	}
}
func printJSON(v any) error {
	e := json.NewEncoder(os.Stdout)
	e.SetIndent("", "  ")
	return e.Encode(v)
}
func run(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return help()
	}
	switch args[0] {
	case "help", "--help", "-h":
		return help()
	case "hardware":
		fs := flag.NewFlagSet("hardware", flag.ContinueOnError)
		interval := fs.Duration("interval", time.Second, "counter sampling interval")
		if e := fs.Parse(args[1:]); e != nil {
			return e
		}
		s, e := hardware.Observe(ctx, *interval)
		if e != nil {
			return e
		}
		return printJSON(s)
	case "init":
		if len(args) != 2 {
			return errors.New("usage: inferctl init lmstudio|llamacpp|comfyui > profile.json")
		}
		c := profile.Default(args[1])
		return printJSON(c)
	case "calibrate", "bench", "run":
		return calibrate(ctx, args[0], args[1:])
	case "compare":
		if len(args) != 2 {
			return errors.New("usage: inferctl compare report.json")
		}
		var r benchmark.Report
		b, e := os.ReadFile(args[1])
		if e != nil {
			return e
		}
		if e = json.Unmarshal(b, &r); e != nil {
			return e
		}
		r.Pareto, r.Recommended = optimizer.Select(r.Results, r.Config.Quality, r.Config.Policy.Mode)
		if r.Error != "" || r.Validation != "controlled protocol completed; real workload measurements" {
			r.Recommended = ""
		}
		return printJSON(r)
	case "reset":
		lock, e := governor.Acquire(ctx, false)
		if e != nil {
			return e
		}
		defer lock.Close()
		return errors.Join(governor.Reset(ctx), docker.Reset(ctx))
	case "docker-plan":
		if len(args) != 2 {
			return errors.New("usage: inferctl docker-plan profile.json")
		}
		c, e := profile.Load(args[1])
		if e != nil {
			return e
		}
		if e = c.Validate(); e != nil {
			return e
		}
		if c.Container == nil {
			return errors.New("profile has no container")
		}
		a, e := docker.Args(*c.Container, c.Candidates[0].Args)
		if e != nil {
			return e
		}
		return printJSON(append([]string{"docker"}, a...))
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}
func help() error {
	fmt.Println(`inferctl: measured local AI resource tuning

  hardware                                Linux hardware/counter snapshot (JSON)
  init lmstudio|llamacpp|comfyui             Print an editable profile
  calibrate BACKEND --profile FILE          Benchmark candidates, recheck baseline, save Pareto/profile
  calibrate lmstudio --model ID --ram-bytes N
  calibrate comfyui --workflow API.json --seed-node NODE.INPUT --ram-bytes N
  bench BACKEND --profile FILE              Benchmark only the first candidate
  run --profile FILE [--dynamic]            Queue admission, run first candidate, optional weight hysteresis
  compare REPORT.json                      Recompute hard constraints and Pareto selection
  docker-plan PROFILE.json                  Print Docker argv without executing it
  reset                                    Stop only owned transient workloads and remove their runtime settings

Options for calibrate/bench/run: --dry-run, --url, --mode interactive|batch|idle|night,
--min-seconds (default 120), --model, --workflow, --seed-node, --ram-bytes,
--wait-admission DURATION (optional bounded queue; original budgets unchanged),
--output REPORT.json (atomic output, also on workload/admission failure),
--thermal (managed native; >=300s), --draft-model (managed llama.cpp).
Results: INFERCTL_STATE or $XDG_STATE_HOME/inferctl. Token: INFERCTL_API_TOKEN.
No root, installation, permanent system changes, model deletion, or global interrupts.`)
	return nil
}
func calibrate(ctx context.Context, action string, args []string) (retErr error) {
	backend := ""
	if action != "run" {
		if len(args) == 0 {
			return errors.New("backend required")
		}
		backend = args[0]
		args = args[1:]
	}
	fs := flag.NewFlagSet(action, flag.ContinueOnError)
	output := fs.String("output", "", "atomically save the final or failed report to this JSON file")
	waitAdmission := fs.Duration("wait-admission", 0, "wait for admission per candidate/lock acquisition (0=fail fast; max 24h)")
	thermal := fs.Bool("thermal", false, "benchmark sustained CPU quota candidates on a managed native backend")
	draft := fs.String("draft-model", "", "comma-separated local GGUF draft paths; managed llama.cpp only")
	path := fs.String("profile", "", "JSON profile")
	model := fs.String("model", "", "model identifier")
	workflow := fs.String("workflow", "", "API workflow")
	seedNode := fs.String("seed-node", "", "seed input, e.g. 3.seed")
	ram := fs.Uint64("ram-bytes", 0, "explicit measured/budgeted RAM requirement")
	url := fs.String("url", "", "endpoint override")
	mode := fs.String("mode", "", "usage mode")
	seconds := fs.Float64("min-seconds", 120, "minimum measured sustained duration")
	dry := fs.Bool("dry-run", false, "print validated plan only")
	dynamic := fs.Bool("dynamic", false, "opt-in runtime native CPUWeight hysteresis")
	if e := fs.Parse(args); e != nil {
		return e
	}
	if *waitAdmission < 0 || *waitAdmission > 24*time.Hour {
		return errors.New("wait-admission must be 0..24h")
	}
	if fs.NArg() != 0 {
		return errors.New("unexpected positional arguments")
	}
	if *output != "" {
		absolute, err := filepath.Abs(*output)
		if err != nil {
			return err
		}
		*output = absolute
		if filepath.Ext(absolute) != ".json" {
			return errors.New("output report must use .json extension")
		}
		if *path != "" {
			profilePath, err := filepath.Abs(*path)
			if err != nil {
				return err
			}
			if absolute == profilePath {
				return errors.New("output report must differ from input profile")
			}
		}
	}

	c := profile.Default(backend)
	var e error
	if *path != "" {
		c, e = profile.Load(*path)
		if e != nil {
			return e
		}
		if backend != "" && backend != c.Backend {
			return errors.New("profile backend mismatch")
		}
	}
	if *model != "" {
		c.Model = *model
	}
	if *workflow != "" {
		c.Workflow = *workflow
	}
	if *seedNode != "" {
		c.SeedNodes = []string{*seedNode}
	}
	if *ram > 0 {
		c.Policy.RequiredRAM = *ram
	}
	if *url != "" {
		c.URL = *url
	}
	if *mode != "" {
		c.Policy.Mode = *mode
	}
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "min-seconds" {
			c.MinSeconds = *seconds
		}
	})
	if *dynamic && c.Policy.PressureWeight < 1 {
		return errors.New("dynamic mode requires an explicit measured policy.pressure_cpu_weight")
	}
	if *dynamic && action != "run" {
		return errors.New("dynamic scheduler is disabled during calibration to preserve fixed controls")
	}
	if e = c.Validate(); e != nil {
		return e
	}
	if _, e = adapters.NewClient(c.URL); e != nil {
		return e
	}
	if c.Workflow != "" {
		c.Workflow, e = filepath.Abs(c.Workflow)
		if e != nil {
			return e
		}
	}
	s, e := hardware.SnapshotNow(ctx)
	if e != nil {
		return e
	}
	if c.HardwareID != "" && c.HardwareID != s.Identity() {
		return errors.New("profile hardware identity differs; recalibrate from an unbound template")
	}

	automatic := action == "calibrate" && len(c.Candidates) == 1
	if automatic {
		c.Candidates = generate(c, s)
	}
	if *thermal {
		if action != "calibrate" || len(c.Command) == 0 || c.Container != nil {
			return errors.New("--thermal requires managed native calibration")
		}
		if c.MinSeconds < 300 {
			c.MinSeconds = 300
		}
		if c.TimeoutSeconds <= c.MinSeconds {
			return errors.New("thermal benchmark timeout too short")
		}
		automatic = false
		base := c.Candidates[0]
		c.Candidates = []profile.Candidate{base}
		for _, ratio := range []float64{.9, 1} {
			v := base
			v.Name = fmt.Sprintf("cpu-cap-%.0f", ratio*100)
			v.Limits.CPUQuota = float64(s.CPU.Threads) * 100 * ratio
			c.Candidates = append(c.Candidates, v)
		}
	}

	if *draft != "" {
		if *thermal {
			return errors.New("run thermal and speculative experiments separately")
		}
		if action != "calibrate" || c.Backend != "llamacpp" || len(c.Command) == 0 {
			return errors.New("--draft-model requires calibrate llamacpp with a managed command")
		}
		automatic = false
		base := c.Candidates[0]
		if base.Speculative {
			return errors.New("speculative baseline must have speculation disabled")
		}
		c.Candidates = []profile.Candidate{base}
		paths := strings.Split(*draft, ",")
		if len(paths) > 8 {
			return errors.New("at most 8 draft models")
		}
		for i, p := range paths {
			p, e = filepath.Abs(p)
			if e != nil {
				return e
			}
			if st, err := os.Stat(p); err != nil || !st.Mode().IsRegular() {
				return fmt.Errorf("draft model not available: %s", p)
			}
			for _, n := range []string{"3", "6"} {
				v := base
				v.Name = fmt.Sprintf("draft-%d-tokens-%s", i, n)
				v.Speculative = true
				v.Args = append(append([]string(nil), base.Args...), "--spec-type", "draft-simple", "--spec-draft-model", p, "--spec-draft-n-max", n)
				c.Candidates = append(c.Candidates, v)
			}
		}
	}

	if action != "calibrate" {
		c.Candidates = c.Candidates[:1]
	}
	if e = c.Validate(); e != nil {
		return e
	}
	// Validation before lifecycle mutations catches unsupported protocol options and missing workflow inputs.
	if e = validateCandidates(c); e != nil {
		return e
	}
	if c.Backend == "comfyui" {
		if _, e = adapters.New(c); e != nil {
			return e
		}
	}
	if *dry {
		return printJSON(struct {
			Hardware string         `json:"hardware_id"`
			Plan     profile.Config `json:"plan"`
		}{s.Identity(), c})
	}
	if c.Policy.RequiredRAM == 0 {
		return errors.New("set --ram-bytes or policy.required_ram_bytes before launching a measured workload")
	}
	lockCtx := ctx
	stopLockWait := func() {}
	if *waitAdmission > 0 {
		lockCtx, stopLockWait = context.WithTimeout(ctx, *waitAdmission)
	}
	lock, e := governor.Acquire(lockCtx, action == "run" || *waitAdmission > 0)
	stopLockWait()
	if e != nil {
		return e
	}
	defer lock.Close()
	report := benchmark.Report{Version: 1, Hardware: s, Config: c, WorkloadHash: profile.Hash(struct {
		Prompt string
		Seed   int64
		Tokens int
	}{c.Prompt, c.Seed, c.Tokens}), Created: time.Now().UTC(), Validation: "incomplete"}
	if c.Workflow != "" {
		b, e := os.ReadFile(c.Workflow)
		if e != nil {
			return e
		}
		report.WorkloadHash = profile.Hash(struct {
			Graph  string
			Seed   int64
			Inputs []string
		}{string(b), c.Seed, c.SeedNodes})
	}
	// The identity includes content, not only the workflow filename.
	key := filepath.Join(s.Identity(), c.Backend, profile.Hash(c.Model + "@" + c.ModelRevision)[:16], profile.Hash(c.Workload + report.WorkloadHash)[:16], c.Policy.Mode)
	stamp := time.Now().UTC().Format("20060102T150405.000000000Z")
	dest := filepath.Join(profile.StateDir(), "benchmarks", key, stamp+".json")
	// A redirected stdout must remain a useful report even when admission/load fails.
	defer func() {
		if retErr != nil {
			report.Error = retErr.Error()
			report.Recommended = ""
		}
		if err := profile.Save(dest, report); err != nil {
			retErr = errors.Join(retErr, err)
			report.Error = retErr.Error()
			report.Recommended = ""
		}
		fmt.Fprintln(os.Stderr, "report:", dest)
		if *output != "" {
			if err := profile.Save(*output, report); err != nil {
				retErr = errors.Join(retErr, err)
				report.Error = retErr.Error()
				report.Recommended = ""
				if saveErr := profile.Save(dest, report); saveErr != nil {
					retErr = errors.Join(retErr, saveErr)
				}
			} else {
				fmt.Fprintln(os.Stderr, "output:", *output)
			}
		}
		if err := printJSON(report); err != nil {
			retErr = errors.Join(retErr, err)
		}
	}()

	logPath := filepath.Join(profile.StateDir(), "events", stamp+".jsonl")
	if e = os.MkdirAll(filepath.Dir(logPath), 0700); e != nil {
		return e
	}
	log, e := os.OpenFile(logPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer log.Close()
	event := func(msg string) {
		b, _ := json.Marshal(map[string]any{"at": time.Now().UTC(), "event": msg})
		_, _ = log.Write(append(b, '\n'))
		fmt.Fprintln(os.Stderr, msg)
	}
	for _, resident := range c.Release {
		releaseCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
		event("model_unload_requested: " + resident.Instance)
		err := adapters.Release(releaseCtx, resident)
		cancel()
		if err != nil {
			report.Validation = "explicit resident release failed"
			_ = profile.Save(dest, report)
			return err
		}
		event("model_unload_confirmed: " + resident.Instance)
	}

	save := func() error { return profile.Save(dest, report) }
	experiment := func(v profile.Candidate) (benchmark.Result, error) {
		admissionCtx := ctx
		stopAdmissionWait := func() {}
		if *waitAdmission > 0 {
			admissionCtx, stopAdmissionWait = context.WithTimeout(ctx, *waitAdmission)
		}
		err := waitForAdmission(admissionCtx, action == "run" || *waitAdmission > 0, 5*time.Second, func(probeCtx context.Context) error {
			h, err := hardware.SnapshotNow(probeCtx)
			if err != nil {
				return err
			}
			if err = governor.Admit(h, c.Policy); err != nil {
				return err
			}
			if c.Quality.SwapMode != "additional" && h.Memory.SwapUsed > c.Quality.MaxSwap {
				return errors.New("host swap already exceeds safety threshold")
			}
			if t := h.MaxTemp(); t != nil && *t >= c.Quality.HardTemp {
				return errors.New("host already at hard thermal limit")
			}
			return nil
		}, event)
		stopAdmissionWait()
		if err != nil {
			return benchmark.Result{}, err
		}

		event("candidate_start: " + v.Name)
		lifecycle, e := benchmark.Start(ctx, c, v, *dynamic, event)
		if e != nil {
			return benchmark.Result{}, e
		}
		b, e := adapters.New(c)
		if e != nil {
			_ = lifecycle.Close()
			return benchmark.Result{}, e
		}
		var observers []func() map[string]uint64
		if lifecycle.Unit != nil {
			observe, err := lifecycle.Unit.Observer(ctx)
			if err != nil {
				_ = lifecycle.Close()
				return benchmark.Result{}, err
			}
			observers = append(observers, observe)
		}
		r := benchmark.Run(ctx, c, v, b, event, observers...)
		if r.Applied == nil {
			r.Applied = map[string]any{}
		}
		if lifecycle.Unit != nil {
			r.Applied["systemd_unit"] = lifecycle.Unit.Name
			r.Applied["systemd_properties"] = governor.Properties(v.Limits)
			r.Applied["verified_controls"] = lifecycle.Verified
			r.Applied["command"] = append(append([]string(nil), c.Command...), v.Args...)
		}
		if lifecycle.Container != nil {
			r.Applied["container"] = c.Container
			r.Applied["container_name"] = lifecycle.Container.Name
			r.Applied["args"] = v.Args
		}
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		closeErr := b.Close(cleanupCtx)
		stopErr := lifecycle.Close()
		if err := errors.Join(closeErr, stopErr); err != nil {
			r.Error = errors.Join(errors.New(r.Error), err).Error()
			return r, err
		}
		event("candidate_end: " + v.Name)
		return r, nil
	}
	for _, v := range c.Candidates {
		r, e := experiment(v)
		if e != nil {
			r.Candidate = v
			r.Error = e.Error()
		}
		report.Results = append(report.Results, r)
		if err := save(); err != nil {
			return err
		}
		if e != nil || ctx.Err() != nil || r.Error != "" && len(report.Results) == 1 {
			return errors.Join(e, ctx.Err(), fmt.Errorf("candidate failed: %s; report: %s", r.Error, dest))
		}
	}
	if automatic {
		for _, v := range optimizer.Refine(c, report.Results) {
			event("adaptive_refinement: " + v.Name)
			r, err := experiment(v)
			if err != nil {
				r.Candidate = v
				r.Error = err.Error()
			}
			report.Results = append(report.Results, r)
			report.Config.Candidates = append(report.Config.Candidates, v)
			if e = save(); e != nil {
				return e
			}
			if err != nil || ctx.Err() != nil {
				return errors.Join(err, ctx.Err())
			}
		}
	}

	// Retest baseline after all candidates to expose changing background load or thermal drift.
	if action == "calibrate" && len(report.Results) > 1 {
		r, e := experiment(c.Candidates[0])
		report.BaselineRecheck = &r
		if e != nil || r.Error != "" {
			report.Validation = "baseline recheck failed"
			_ = save()
			return fmt.Errorf("baseline recheck failed; report: %s", dest)
		}
		ratio := r.MedianPerformance / report.Results[0].MedianPerformance
		if math.Abs(ratio-1) > c.Quality.BaselineDrift {
			report.Validation = "baseline drift exceeded threshold"
			_ = save()
			return fmt.Errorf("baseline drift %.2f%%; recommendation withheld: %s", (ratio-1)*100, dest)
		}
	}
	report.Validation = "controlled protocol completed; real workload measurements"
	if c.MinSeconds < 120 {
		report.Validation = "exploratory short benchmark; thermal validation pending"
	}
	report.Pareto, report.Recommended = optimizer.Select(report.Results, c.Quality, c.Policy.Mode)
	if c.MinSeconds < 120 || *dynamic {
		report.Recommended = ""
	}
	if *dynamic {
		report.Validation = "dynamic execution; fixed-configuration calibration required"
	}
	if e = save(); e != nil {
		return e
	}
	if report.Recommended != "" {
		for _, r := range report.Results {
			if r.Candidate.Name == report.Recommended {
				selected := c
				selected.HardwareID = s.Identity()
				selected.Candidates = []profile.Candidate{r.Candidate}
				if e = profile.Save(filepath.Join(profile.StateDir(), "profiles", key, "recommended.json"), selected); e != nil {
					return e
				}
			}
		}
	}
	return nil
}
func generate(c profile.Config, h hardware.Snapshot) []profile.Candidate {
	base := c.Candidates[0]
	out := []profile.Candidate{base}
	add := func(name string, load map[string]any, args []string) {
		v := base
		v.Name = name
		v.Load = load
		v.Args = args
		out = append(out, v)
	}
	switch c.Backend {
	case "lmstudio":
		for _, batch := range []int{128, 256, 512} {
			load := map[string]any{}
			for k, v := range base.Load {
				load[k] = v
			}
			load["eval_batch_size"] = batch
			add(fmt.Sprintf("batch-%d", batch), load, nil)
		}
	case "llamacpp":
		if len(c.Command) > 0 {
			seen := map[int]bool{}
			for _, n := range []int{max(1, h.CPU.PhysicalCores/2), max(1, h.CPU.PhysicalCores), max(1, h.CPU.Threads), max(1, int(float64(h.CPU.Threads)*(1-c.Policy.CPUReserve/100)))} {
				if !seen[n] {
					seen[n] = true
					add(fmt.Sprintf("threads-%d", n), nil, append(append([]string(nil), base.Args...), "--threads", fmt.Sprint(n)))
				}
			}
		}
	case "comfyui":
		if len(c.Command) > 0 || c.Container != nil {
			for _, headroom := range []string{"0.5", "1.0", "1.5", "2.0"} {
				add("headroom-"+headroom, nil, append(append([]string(nil), base.Args...), "--reserve-vram", headroom))
			}
		}
	}
	return out
}
func validateCandidates(c profile.Config) error {
	for _, v := range c.Candidates {
		if c.Backend != "lmstudio" && len(v.Load) > 0 {
			return errors.New("load settings are supported only by LM Studio; native/container parameters belong in args")
		}
		if c.Container != nil && profile.Hash(v.Limits) != profile.Hash(profile.Limits{CPUWeight: 100, IOWeight: 100}) {
			return errors.New("candidate systemd limits do not apply to Docker; use container.cpus and container.memory_bytes")
		}
		if c.Backend == "lmstudio" {
			for k := range v.Load {
				switch k {
				case "context_length", "eval_batch_size", "flash_attention", "offload_kv_cache_to_gpu", "parallel":
				default:
					return fmt.Errorf("unsupported LM Studio REST setting %q", k)
				}
			}
		}
		if len(v.Args) > 0 && len(c.Command) == 0 && c.Container == nil {
			return errors.New("candidate args require managed command/container")
		}
	}
	if c.Container != nil {
		for _, v := range c.Candidates {
			if _, e := docker.Args(*c.Container, v.Args); e != nil {
				return e
			}
		}
	}
	// A pre-existing listener could otherwise make a failed managed process appear ready.
	if len(c.Command) > 0 || c.Container != nil {
		if !strings.HasPrefix(c.URL, "http://127.0.0.1:") {
			return errors.New("managed backends require an explicit IPv4 loopback URL")
		}
	}
	return nil
}
