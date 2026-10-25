package adapters

import (
	"context"
	"encoding/json"
	"fmt"
	"inferctl/internal/profile"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSSEFramesAndTruncation(t *testing.T) {
	var got []string
	e := ReadSSE(strings.NewReader(": ping\r\nevent: message.delta\r\ndata: {\"a\":\r\ndata: 1}\r\n\r\nevent: chat.end\ndata: {}"), func(k string, b []byte) error { got = append(got, k+string(b)); return nil })
	if e != nil || len(got) != 2 || got[0] != "message.delta{\"a\":\n1}" {
		t.Fatal(got, e)
	}
}
func TestLMStudioLifecycleAndStreaming(t *testing.T) {
	unloaded := ""
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/models":
			fmt.Fprint(w, `{"models":[{"key":"model","loaded_instances":[]}]}`)
		case "/api/v1/models/load":
			fmt.Fprint(w, `{"instance_id":"owned-123","load_config":{"context_length":4096}}`)
		case "/api/v1/models/unload":
			var v map[string]string
			_ = json.NewDecoder(r.Body).Decode(&v)
			unloaded = v["instance_id"]
			fmt.Fprint(w, `{}`)
		case "/api/v1/chat":
			var v map[string]any
			_ = json.NewDecoder(r.Body).Decode(&v)
			if v["model"] != "owned-123" || v["store"] != false {
				t.Error(v)
			}
			w.Header().Set("Content-Type", "text/event-stream")
			fmt.Fprint(w, "event: message.delta\ndata: {\"content\":\"hello\"}\n\nevent: chat.end\ndata: {\"result\":{\"stats\":{\"tokens_per_second\":10,\"input_tokens\":20,\"total_output_tokens\":5}}}\n\n")
		}
	}))
	defer srv.Close()
	c := profile.Default("lmstudio")
	c.URL = srv.URL
	c.Model = "model"
	b, e := New(c)
	if e != nil {
		t.Fatal(e)
	}
	_, e = b.Prepare(context.Background(), profile.Candidate{Load: map[string]any{"context_length": 4096}})
	if e != nil {
		t.Fatal(e)
	}
	m, e := b.Run(context.Background(), 0)
	if e != nil || m.TPS != 10 || m.OutputTokens != 5 || m.TTFT <= 0 {
		t.Fatal(m, e)
	}
	if e = b.Close(context.Background()); e != nil || unloaded != "owned-123" {
		t.Fatal(unloaded, e)
	}
}
func TestLMIncompleteStreamRejected(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "event: message.delta\ndata: {\"content\":\"partial\"}\n\n")
	}))
	defer srv.Close()
	c := profile.Default("lmstudio")
	h, _ := NewClient(srv.URL)
	l := LMStudio{Client: h, Config: c, Instance: "owned"}
	if _, e := l.Run(context.Background(), 0); e == nil {
		t.Fatal("accepted truncated stream")
	}
}
func TestLMRefusesResidentAndUnsupportedOptions(t *testing.T) {
	loads := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "POST" {
			loads++
		}
		fmt.Fprint(w, `{"models":[{"key":"model","loaded_instances":[{"id":"someone-else"}]}]}`)
	}))
	defer srv.Close()
	c := profile.Default("lmstudio")
	c.Model = "model"
	h, _ := NewClient(srv.URL)
	l := LMStudio{Client: h, Config: c}
	if _, e := l.Prepare(context.Background(), profile.Candidate{}); e == nil {
		t.Fatal("adopted resident model")
	}
	if _, e := l.Prepare(context.Background(), profile.Candidate{Load: map[string]any{"threads": 4}}); e == nil {
		t.Fatal("silently ignored threads")
	}
	if loads != 0 {
		t.Fatal("mutated external model")
	}
}
func TestComfySeedSequenceAndCacheRejection(t *testing.T) {
	path := filepath.Join(t.TempDir(), "workflow.json")
	_ = os.WriteFile(path, []byte(`{"3":{"class_type":"KSampler","inputs":{"seed":42}}}`), 0600)
	var seeds []float64
	cached := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/prompt":
			var body struct {
				Prompt map[string]struct {
					Inputs map[string]float64 `json:"inputs"`
				} `json:"prompt"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			seeds = append(seeds, body.Prompt["3"].Inputs["seed"])
			fmt.Fprint(w, `{"prompt_id":"owned"}`)
		case strings.HasPrefix(r.URL.Path, "/history/"):
			msg := `[]`
			if cached {
				msg = `[["execution_cached",{"nodes":["3"]}]]`
			}
			fmt.Fprintf(w, `{"owned":{"outputs":{"9":{}},"status":{"completed":true,"status_str":"success","messages":%s}}}`, msg)
		}
	}))
	defer srv.Close()
	c := profile.Default("comfyui")
	c.Workflow = path
	c.SeedNodes = []string{"3.seed"}
	h, _ := NewClient(srv.URL)
	b, e := NewComfy(h, c)
	if e != nil {
		t.Fatal(e)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if _, e = b.Run(ctx, 0); e != nil {
		t.Fatal(e)
	}
	cached = true
	if _, e = b.Run(ctx, 1); e == nil {
		t.Fatal("cached generation accepted")
	}
	if len(seeds) != 2 || seeds[0] != 42 || seeds[1] != 43 {
		t.Fatal(seeds)
	}
}
func TestBearerTokenNotRedirected(t *testing.T) {
	hit := false
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { hit = true }))
	defer target.Close()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, 307) }))
	defer origin.Close()
	h, _ := NewClient(origin.URL)
	h.Token = "secret"
	if e := h.JSON(context.Background(), "GET", "/", nil, nil); e == nil || hit {
		t.Fatal("redirect followed")
	}
}

func TestExplicitReleaseRejectsMismatchedIdentity(t *testing.T) {
	posts := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "POST" {
			posts++
		}
		fmt.Fprint(w, `{"models":[{"key":"different-model","loaded_instances":[{"id":"named-instance"}]}]}`)
	}))
	defer srv.Close()
	e := Release(context.Background(), profile.Resident{Backend: "lmstudio", URL: srv.URL, Model: "expected-model", Instance: "named-instance"})
	if e == nil || posts != 0 {
		t.Fatal("released mismatched model", e, posts)
	}
}

func TestLlamaModelIdentityAndDraftAcceptance(t *testing.T) {
	model := "/models/main.gguf"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/props" {
			_ = json.NewEncoder(w).Encode(map[string]any{"model_path": model})
			return
		}
		fmt.Fprint(w, "data: {\"content\":\"hello\"}\n\ndata: {\"stop\":true,\"timings\":{\"predicted_per_second\":12,\"predicted_n\":10,\"prompt_n\":5,\"draft_n\":20,\"draft_n_accepted\":15}}\n\n")
	}))
	defer srv.Close()
	h, _ := NewClient(srv.URL)
	c := profile.Default("llamacpp")
	c.Model = model
	l := LlamaCPP{Client: h, Config: c}
	if _, e := l.Prepare(context.Background(), profile.Candidate{Speculative: true}); e != nil {
		t.Fatal(e)
	}
	m, e := l.Run(context.Background(), 0)
	if e != nil || m.Extra["draft_acceptance_ratio"] != .75 {
		t.Fatal(m, e)
	}
	model = "/models/other.gguf"
	if _, e = l.Prepare(context.Background(), profile.Candidate{}); e == nil {
		t.Fatal("wrong model accepted")
	}
}

func TestLMParallelExperimentalOptionRequiresAcknowledgement(t *testing.T) {
	for _, acknowledged := range []int{1, 4} {
		t.Run(fmt.Sprint(acknowledged), func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case "/api/v1/models":
					fmt.Fprint(w, `{"models":[{"key":"test","loaded_instances":[]}]}`)
				case "/api/v1/models/load":
					var body map[string]any
					_ = json.NewDecoder(r.Body).Decode(&body)
					if body["parallel"] != float64(1) {
						t.Error("parallel option not sent", body)
					}
					_ = json.NewEncoder(w).Encode(map[string]any{"instance_id": "owned", "load_config": map[string]any{"parallel": acknowledged}})
				}
			}))
			defer srv.Close()
			h, _ := NewClient(srv.URL)
			c := profile.Default("lmstudio")
			c.Model = "test"
			l := LMStudio{Client: h, Config: c}
			_, err := l.Prepare(context.Background(), profile.Candidate{Load: map[string]any{"parallel": 1}})
			if (err == nil) != (acknowledged == 1) {
				t.Fatal("ignored parallel setting not detected", err)
			}
			if l.Instance != "owned" {
				t.Fatal("loaded instance lost ownership; cleanup would be impossible")
			}
		})
	}
}
func TestLMParallelRejectsInvalidValuesBeforeRequests(t *testing.T) {
	h, _ := NewClient("http://127.0.0.1:1")
	l := LMStudio{Client: h}
	for _, value := range []any{0, -1, 1.5, true, "1", nil} {
		_, err := l.Prepare(context.Background(), profile.Candidate{Load: map[string]any{"parallel": value}})
		if err == nil || err.Error() != "parallel must be a positive integer" {
			t.Fatalf("invalid parallel %v not rejected locally: %v", value, err)
		}
	}
}

func TestExplicitReleaseUnloadsOnlyNamedInstance(t *testing.T) {
	released := false
	unloads := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/models":
			loaded := []map[string]any{{"id": "wanted"}}
			if released {
				loaded = []map[string]any{}
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"models": []map[string]any{
				{"key": "target", "loaded_instances": loaded},
				{"key": "other", "loaded_instances": []map[string]any{{"id": "do-not-unload"}}},
			}})
		case "/api/v1/models/unload":
			var body map[string]string
			_ = json.NewDecoder(r.Body).Decode(&body)
			if body["instance_id"] != "wanted" {
				t.Error("attempted to unload another instance", body)
			}
			unloads++
			released = true
			fmt.Fprint(w, `{}`)
		default:
			t.Error("unexpected API route", r.URL.Path)
		}
	}))
	defer srv.Close()
	err := Release(context.Background(), profile.Resident{Backend: "lmstudio", URL: srv.URL, Model: "target", Instance: "wanted"})
	if err != nil || !released || unloads != 1 {
		t.Fatal("exact release failed", err, released, unloads)
	}
}
