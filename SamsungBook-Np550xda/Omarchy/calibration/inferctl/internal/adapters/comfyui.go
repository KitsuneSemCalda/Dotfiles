package adapters

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"inferctl/internal/profile"
	"net/url"
	"os"
	"strings"
	"time"
)

type Comfy struct {
	Client *Client
	Config profile.Config
	Graph  map[string]any
}

func NewComfy(h *Client, c profile.Config) (*Comfy, error) {
	b, e := os.ReadFile(c.Workflow)
	if e != nil {
		return nil, e
	}
	if len(b) > 16<<20 {
		return nil, errors.New("workflow exceeds 16 MiB")
	}
	var graph map[string]any
	if e = json.Unmarshal(b, &graph); e != nil {
		return nil, e
	}
	if _, ok := graph["nodes"]; ok {
		return nil, errors.New("export workflow in API format, not UI format")
	}
	for _, p := range c.SeedNodes {
		node, key, ok := strings.Cut(p, ".")
		if !ok {
			return nil, errors.New("seed_nodes entries must be node_id.input_name")
		}
		n, ok := graph[node].(map[string]any)
		if !ok {
			return nil, fmt.Errorf("missing seed node %s", node)
		}
		in, ok := n["inputs"].(map[string]any)
		if !ok {
			return nil, fmt.Errorf("node %s missing inputs", node)
		}
		if _, ok := in[key].(float64); !ok {
			return nil, fmt.Errorf("seed input %s must be numeric", p)
		}
	}
	return &Comfy{Client: h, Config: c, Graph: graph}, nil
}
func (c *Comfy) Prepare(ctx context.Context, v profile.Candidate) (map[string]any, error) {
	if len(v.Load) > 0 {
		return nil, errors.New("ComfyUI runtime settings require managed server args; workflow edits are not tuning")
	}
	var q struct {
		Running []any `json:"queue_running"`
		Pending []any `json:"queue_pending"`
	}
	if e := c.Client.JSON(ctx, "GET", "/queue", nil, &q); e != nil {
		return nil, e
	}
	if len(q.Running)+len(q.Pending) > 0 {
		return nil, errors.New("ComfyUI queue is busy")
	}
	var stats map[string]any
	e := c.Client.JSON(ctx, "GET", "/system_stats", nil, &stats)
	return stats, e
}
func (c *Comfy) Close(context.Context) error { return nil }
func (c *Comfy) Run(ctx context.Context, i int) (Measurement, error) {
	m := Measurement{Extra: map[string]any{}}
	b, _ := json.Marshal(c.Graph)
	var graph map[string]any
	_ = json.Unmarshal(b, &graph)
	// Use the same deterministic sequence across candidates; fresh seeds defeat cached diffusion outputs.
	for _, p := range c.Config.SeedNodes {
		n, k, _ := strings.Cut(p, ".")
		graph[n].(map[string]any)["inputs"].(map[string]any)[k] = c.Config.Seed + int64(i)
	}
	start := time.Now()
	var result struct {
		ID     string         `json:"prompt_id"`
		Errors map[string]any `json:"node_errors"`
	}
	if e := c.Client.JSON(ctx, "POST", "/prompt", map[string]any{"prompt": graph, "client_id": "inferctl"}, &result); e != nil {
		return m, e
	}
	if result.ID == "" || len(result.Errors) > 0 {
		return m, fmt.Errorf("invalid workflow submission: %v", result.Errors)
	}
	m.Extra["prompt_id"] = result.ID
	m.Extra["seed"] = c.Config.Seed + int64(i)
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return m, fmt.Errorf("%w; submitted prompt %s may still run; no global interrupt issued", ctx.Err(), result.ID)
		case <-ticker.C:
			var history map[string]struct {
				Outputs map[string]any `json:"outputs"`
				Status  struct {
					Completed bool              `json:"completed"`
					Status    string            `json:"status_str"`
					Messages  []json.RawMessage `json:"messages"`
				} `json:"status"`
			}
			if e := c.Client.JSON(ctx, "GET", "/history/"+url.PathEscape(result.ID), nil, &history); e != nil {
				return m, e
			}
			h, ok := history[result.ID]
			if !ok {
				continue
			}
			if h.Status.Status == "error" {
				return m, errors.New("ComfyUI execution failed")
			}
			if !h.Status.Completed {
				continue
			}
			if h.Status.Status != "success" {
				return m, fmt.Errorf("ComfyUI status %q", h.Status.Status)
			}
			for _, raw := range h.Status.Messages {
				var msg []json.RawMessage
				if json.Unmarshal(raw, &msg) != nil || len(msg) != 2 {
					continue
				}
				var kind string
				_ = json.Unmarshal(msg[0], &kind)
				if kind == "execution_cached" {
					var cached struct {
						Nodes []string `json:"nodes"`
					}
					_ = json.Unmarshal(msg[1], &cached)
					m.Extra["cached_nodes"] = cached.Nodes
					for _, p := range c.Config.SeedNodes {
						n, _, _ := strings.Cut(p, ".")
						for _, id := range cached.Nodes {
							if id == n {
								return m, errors.New("seed node served from cache: invalid generation benchmark")
							}
						}
					}
				}
			}
			m.Seconds = time.Since(start).Seconds()
			if c.Config.ImagesPerRun > 0 {
				m.Extra["seconds_per_image"] = m.Seconds / float64(c.Config.ImagesPerRun)
			}
			if c.Config.FramesPerRun > 0 {
				m.Extra["seconds_per_frame"] = m.Seconds / float64(c.Config.FramesPerRun)
				m.Extra["frames_per_second"] = float64(c.Config.FramesPerRun) / m.Seconds
			}
			m.OutputHash = profile.Hash(h.Outputs)
			m.Extra["history_status"] = h.Status
			m.Extra["output_nodes"] = len(h.Outputs)
			return m, nil
		}
	}
}
