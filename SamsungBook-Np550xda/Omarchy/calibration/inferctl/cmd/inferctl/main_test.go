package main

import (
	"context"
	"encoding/json"
	"fmt"
	"inferctl/internal/benchmark"
	"inferctl/internal/profile"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestCalibrationEndToEndSyntheticAndFailurePersistence(t *testing.T) {
	t.Setenv("INFERCTL_STATE", t.TempDir())
	loads, unloads := 0, 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/models":
			fmt.Fprint(w, `{"models":[{"key":"synthetic","loaded_instances":[]}]}`)
		case "/api/v1/models/load":
			loads++
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			delete(body, "model")
			delete(body, "echo_load_config")
			_ = json.NewEncoder(w).Encode(map[string]any{"instance_id": "owned", "load_config": body})
		case "/api/v1/models/unload":
			unloads++
			fmt.Fprint(w, `{}`)
		case "/api/v1/chat":
			fmt.Fprint(w, "event: message.delta\ndata: {\"content\":\"test\"}\n\nevent: chat.end\ndata: {\"result\":{\"stats\":{\"tokens_per_second\":10,\"input_tokens\":4,\"total_output_tokens\":4}}}\n\n")
		}
	}))
	defer srv.Close()
	c := profile.Default("lmstudio")
	c.Model = "synthetic"
	c.URL = srv.URL
	c.Policy.RequiredRAM = 1
	c.MinSeconds = 0
	c.TimeoutSeconds = 10
	c.Quality.MaxSwap = ^uint64(0)
	c.Quality.HardTemp = 1000
	v := c.Candidates[0]
	v.Name = "other"
	c.Candidates = append(c.Candidates, v)
	p := filepath.Join(t.TempDir(), "profile.json")
	if e := profile.Save(p, c); e != nil {
		t.Fatal(e)
	}
	if e := run(context.Background(), []string{"calibrate", "lmstudio", "--profile", p}); e != nil {
		t.Fatal(e)
	}
	if loads != 3 || unloads != 3 {
		t.Fatal("lifecycle mismatch", loads, unloads)
	}
	var reports []string
	_ = filepath.WalkDir(profile.StateDir(), func(p string, d os.DirEntry, e error) error {
		if e == nil && !d.IsDir() && filepath.Ext(p) == ".json" {
			reports = append(reports, p)
		}
		return nil
	})
	if len(reports) != 1 {
		t.Fatal(reports)
	}
	b, e := os.ReadFile(reports[0])
	if e != nil {
		t.Fatal(e)
	}
	var report benchmark.Report
	if e = json.Unmarshal(b, &report); e != nil {
		t.Fatal(e)
	}
	if report.Recommended != "" || len(report.Results) != 2 || report.BaselineRecheck == nil {
		t.Fatal("short run falsely recommended or missing recheck")
	}
	c.URL = "http://127.0.0.1:1"
	if e = profile.Save(p, c); e != nil {
		t.Fatal(e)
	}
	if e = run(context.Background(), []string{"bench", "lmstudio", "--profile", p}); e == nil {
		t.Fatal("unreachable backend accepted")
	}
}

func TestAdmissionFailureEmitsStructuredReportToStdout(t *testing.T) {
	t.Setenv("INFERCTL_STATE", t.TempDir())
	c := profile.Default("lmstudio")
	c.Model = "must-not-load"
	c.URL = "http://127.0.0.1:1"
	c.Policy.RequiredRAM = ^uint64(0)
	path := filepath.Join(t.TempDir(), "profile.json")
	if err := profile.Save(path, c); err != nil {
		t.Fatal(err)
	}
	out, err := os.CreateTemp(t.TempDir(), "stdout-*.json")
	if err != nil {
		t.Fatal(err)
	}
	defer out.Close()
	previous := os.Stdout
	os.Stdout = out
	defer func() { os.Stdout = previous }()
	reportPath := filepath.Join(t.TempDir(), "external", "report.json")
	err = run(context.Background(), []string{"bench", "lmstudio", "--profile", path, "--output", reportPath})
	if err == nil {
		t.Fatal("admitted impossible RAM budget")
	}
	if _, err = out.Seek(0, 0); err != nil {
		t.Fatal(err)
	}
	var r benchmark.Report
	if err = json.NewDecoder(out).Decode(&r); err != nil {
		t.Fatal("failure left redirected stdout empty", err)
	}
	if r.Error == "" || len(r.Results) != 1 || r.Results[0].Error == "" || len(r.Results[0].Runs) != 0 || r.Recommended != "" {
		t.Fatal("invalid failure report", r)
	}
	b, err := os.ReadFile(reportPath)
	if err != nil {
		t.Fatal("atomic external failure report missing", err)
	}
	var external benchmark.Report
	if err = json.Unmarshal(b, &external); err != nil || profile.Hash(external) != profile.Hash(r) {
		t.Fatal("external report differs from stdout", err)
	}

}

func TestOutputCannotOverwriteInputProfile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.json")
	c := profile.Default("lmstudio")
	c.Model = "test"
	if err := profile.Save(path, c); err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(path)
	if err := run(context.Background(), []string{"bench", "lmstudio", "--profile", path, "--output", path}); err == nil {
		t.Fatal("input profile accepted as output")
	}
	after, _ := os.ReadFile(path)
	if string(before) != string(after) {
		t.Fatal("input profile changed")
	}
}
