package adapters

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"inferctl/internal/profile"
	"path/filepath"
	"strings"
	"time"
)

type LlamaCPP struct {
	Client      *Client
	Config      profile.Config
	speculative bool
}

func (l *LlamaCPP) Prepare(ctx context.Context, c profile.Candidate) (map[string]any, error) {
	if len(c.Load) > 0 {
		return nil, fmt.Errorf("llama.cpp load settings belong in managed command args")
	}
	var props map[string]any
	e := l.Client.JSON(ctx, "GET", "/props", nil, &props)
	if e != nil {
		return props, e
	}
	actual, ok := props["model_path"].(string)
	if !ok || actual == "" {
		return props, errors.New("llama.cpp did not identify model_path")
	}
	if filepath.Clean(actual) != filepath.Clean(l.Config.Model) {
		return props, fmt.Errorf("llama.cpp model mismatch: actual %q, profile %q", actual, l.Config.Model)
	}
	l.speculative = c.Speculative
	return props, nil
}
func (l *LlamaCPP) Close(context.Context) error { return nil }
func (l *LlamaCPP) Run(ctx context.Context, i int) (Measurement, error) {
	start := time.Now()
	m := Measurement{Extra: map[string]any{}}
	r, e := l.Client.Request(ctx, "POST", "/completion", map[string]any{"prompt": l.Config.Prompt, "n_predict": l.Config.Tokens, "seed": l.Config.Seed, "temperature": 0, "stream": true, "cache_prompt": false})
	if e != nil {
		return m, e
	}
	defer r.Body.Close()
	var text strings.Builder
	var first time.Time
	stopped := false
	e = ReadSSE(r.Body, func(_ string, data []byte) error {
		if string(data) == "[DONE]" {
			return nil
		}
		var v struct {
			Content string `json:"content"`
			Stop    bool   `json:"stop"`
			Error   any    `json:"error"`
			Timings struct {
				TPS       float64 `json:"predicted_per_second"`
				Draft     *int64  `json:"draft_n"`
				Accepted  *int64  `json:"draft_n_accepted"`
				PromptTPS float64 `json:"prompt_per_second"`
				Predicted int     `json:"predicted_n"`
				Prompt    int     `json:"prompt_n"`
			} `json:"timings"`
		}
		if e := json.Unmarshal(data, &v); e != nil {
			return e
		}
		if v.Error != nil {
			return fmt.Errorf("llama.cpp stream error: %v", v.Error)
		}
		if v.Content != "" {
			if first.IsZero() {
				first = time.Now()
			}
			text.WriteString(v.Content)
		}
		if v.Stop {
			stopped = true
			m.TPS = v.Timings.TPS
			m.OutputTokens = v.Timings.Predicted
			if v.Timings.Draft != nil && v.Timings.Accepted != nil {
				draft, accepted := *v.Timings.Draft, *v.Timings.Accepted
				if draft < 0 || accepted < 0 || accepted > draft {
					return errors.New("invalid speculative decoding counters")
				}
				m.Extra["draft_tokens"] = draft
				m.Extra["accepted_draft_tokens"] = accepted
				if draft > 0 {
					if !l.speculative {
						return errors.New("unexpected speculation in non-speculative baseline/candidate")
					}
					m.Extra["draft_acceptance_ratio"] = float64(accepted) / float64(draft)
				}
			}
			m.InputTokens = v.Timings.Prompt
			if v.Timings.PromptTPS > 0 {
				n := v.Timings.PromptTPS
				m.PromptTPS = &n
			}
			var raw map[string]any
			_ = json.Unmarshal(data, &raw)
			m.Extra["timings"] = raw["timings"]
			if spec, ok := raw["speculative"]; ok {
				m.Extra["speculative"] = spec
			}
		}
		return nil
	})
	m.Seconds = time.Since(start).Seconds()
	if !first.IsZero() {
		m.TTFT = first.Sub(start).Seconds()
	}
	m.OutputHash = profile.Hash(text.String())
	if e != nil {
		return m, e
	}
	if !stopped || m.TPS <= 0 || m.OutputTokens < 2 || first.IsZero() {
		return m, errors.New("missing llama.cpp completion timings")
	}
	if l.speculative {
		if _, ok := m.Extra["draft_acceptance_ratio"]; !ok {
			return m, errors.New("draft candidate produced no acceptance counters; speculation not verified")
		}
	}
	return m, nil
}
