package adapters

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"inferctl/internal/profile"
)

type LMStudio struct {
	Client   *Client
	Config   profile.Config
	Instance string
}

func (l *LMStudio) Prepare(ctx context.Context, c profile.Candidate) (map[string]any, error) {
	allowed := map[string]bool{"context_length": true, "eval_batch_size": true, "parallel": true, "flash_attention": true, "offload_kv_cache_to_gpu": true}
	body := map[string]any{"model": l.Config.Model, "echo_load_config": true}
	for k, v := range c.Load {
		if !allowed[k] {
			return nil, fmt.Errorf("LM Studio REST does not expose %q; use a managed llama.cpp command for native flags", k)
		}
		if k == "parallel" {
			b, err := json.Marshal(v)
			if err != nil {
				return nil, err
			}
			var n int64
			if json.Unmarshal(b, &n) != nil || n < 1 {
				return nil, errors.New("parallel must be a positive integer")
			}
		}
		body[k] = v
	}
	// Refuse to adopt or evict an instance loaded by someone else.
	var listing struct {
		Models []struct {
			Key    string `json:"key"`
			Loaded []struct {
				ID string `json:"id"`
			} `json:"loaded_instances"`
		} `json:"models"`
	}
	if e := l.Client.JSON(ctx, "GET", "/api/v1/models", nil, &listing); e != nil {
		return nil, e
	}
	if listing.Models == nil {
		return nil, errors.New("model list missing models array")
	}
	found := false
	for _, m := range listing.Models {
		if m.Key == l.Config.Model {
			found = true
		}
		if (m.Key == l.Config.Model || l.Config.Policy.Exclusive) && len(m.Loaded) > 0 {
			return nil, errors.New("target model already resident; unload it explicitly before calibration to preserve ownership and load settings")
		}
	}
	if !found {
		return nil, errors.New("model key absent from inventory; provide exact local model key")
	}

	var result struct {
		Instance string         `json:"instance_id"`
		Config   map[string]any `json:"load_config"`
		LoadTime float64        `json:"load_time_seconds"`
	}
	if e := l.Client.JSON(ctx, "POST", "/api/v1/models/load", body, &result); e != nil {
		return nil, e
	}
	if result.Instance == "" {
		return nil, errors.New("load response missing instance_id")
	}
	l.Instance = result.Instance
	for k, v := range c.Load {
		if profile.Hash(result.Config[k]) != profile.Hash(v) {
			return nil, fmt.Errorf("backend did not acknowledge load option %s", k)
		}
	}
	return map[string]any{"load_config": result.Config, "load_seconds": result.LoadTime, "instance_id": result.Instance}, nil
}
func (l *LMStudio) Run(ctx context.Context, iteration int) (Measurement, error) {
	started := time.Now()
	m := Measurement{Extra: map[string]any{}}
	// The documented REST API has no seed field: temperature=0 is recorded, not claimed bit-deterministic.
	body := map[string]any{"model": l.Instance, "input": l.Config.Prompt, "temperature": 0, "max_output_tokens": l.Config.Tokens, "stream": true, "store": false}
	r, e := l.Client.Request(ctx, "POST", "/api/v1/chat", body)
	if e != nil {
		return m, e
	}
	defer r.Body.Close()
	var text strings.Builder
	var first, ppStart time.Time
	var pp float64
	ended := false
	e = ReadSSE(r.Body, func(kind string, data []byte) error {
		var event struct {
			Type    string `json:"type"`
			Content string `json:"content"`
			Result  struct {
				Stats struct {
					TPS    float64 `json:"tokens_per_second"`
					TTFT   float64 `json:"time_to_first_token_seconds"`
					Input  int     `json:"input_tokens"`
					Output int     `json:"total_output_tokens"`
				} `json:"stats"`
			} `json:"result"`
		}
		if e := json.Unmarshal(data, &event); e != nil {
			return e
		}
		if kind == "" {
			kind = event.Type
		}
		switch kind {
		case "error":
			return errors.New("backend emitted SSE error")
		case "prompt_processing.start":
			ppStart = time.Now()
		case "prompt_processing.end":
			if !ppStart.IsZero() {
				pp = time.Since(ppStart).Seconds()
			}
		case "message.delta", "reasoning.delta":
			if first.IsZero() && event.Content != "" {
				first = time.Now()
			}
			text.WriteString(event.Content)
		case "chat.end":
			ended = true
			m.TPS = event.Result.Stats.TPS
			m.InputTokens = event.Result.Stats.Input
			m.OutputTokens = event.Result.Stats.Output
			m.Extra["server_ttft_seconds"] = event.Result.Stats.TTFT
		}
		return nil
	})
	m.Seconds = time.Since(started).Seconds()
	if !first.IsZero() {
		m.TTFT = first.Sub(started).Seconds()
	}
	if pp > 0 {
		m.Extra["prompt_processing_wall_seconds"] = pp
		m.Extra["prompt_tps_caveat"] = "input tokens may include backend prompt-cache hits"
		v := float64(m.InputTokens) / pp
		m.PromptTPS = &v
	}
	m.OutputHash = profile.Hash(text.String())
	if e != nil {
		return m, e
	}
	if !ended || m.TPS <= 0 || m.OutputTokens < 2 || first.IsZero() {
		return m, errors.New("incomplete stream or missing token metrics")
	}
	return m, nil
}
func (l *LMStudio) Close(ctx context.Context) error {
	if l.Instance == "" {
		return nil
	}
	id := l.Instance
	if e := l.Client.JSON(ctx, "POST", "/api/v1/models/unload", map[string]any{"instance_id": id}, nil); e != nil {
		return e
	}
	for {
		var listing struct {
			Models []struct {
				Loaded []struct {
					ID string `json:"id"`
				} `json:"loaded_instances"`
			} `json:"models"`
		}
		if e := l.Client.JSON(ctx, "GET", "/api/v1/models", nil, &listing); e != nil {
			return e
		}
		if listing.Models == nil {
			return errors.New("cannot verify unload: missing models array")
		}
		resident := false
		for _, m := range listing.Models {
			for _, v := range m.Loaded {
				if v.ID == id {
					resident = true
				}
			}
		}
		if !resident {
			l.Instance = ""
			return nil
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("unload not confirmed: %w", ctx.Err())
		case <-time.After(250 * time.Millisecond):
		}
	}
}

// ReadSSE handles CRLF and multi-line data, with an explicit upper bound per event.
func ReadSSE(r io.Reader, fn func(string, []byte) error) error {
	s := bufio.NewScanner(r)
	s.Buffer(make([]byte, 4096), 4<<20)
	kind := ""
	var data []string
	flush := func() error {
		if len(data) == 0 {
			return nil
		}
		e := fn(kind, []byte(strings.Join(data, "\n")))
		data = nil
		kind = ""
		return e
	}
	for s.Scan() {
		line := s.Text()
		if line == "" {
			if e := flush(); e != nil {
				return e
			}
			continue
		}
		if strings.HasPrefix(line, ":") {
			continue
		}
		k, v, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		v = strings.TrimPrefix(v, " ")
		switch k {
		case "event":
			kind = v
		case "data":
			data = append(data, v)
		}
	}
	if e := s.Err(); e != nil {
		return e
	}
	return flush()
}
