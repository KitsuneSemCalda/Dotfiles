package adapters

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"

	"inferctl/internal/profile"
)

type Measurement struct {
	Seconds      float64        `json:"seconds"`
	TPS          float64        `json:"tps,omitempty"`
	TTFT         float64        `json:"ttft_seconds,omitempty"`
	PromptTPS    *float64       `json:"prompt_tps,omitempty"`
	OutputTokens int            `json:"output_tokens,omitempty"`
	InputTokens  int            `json:"input_tokens,omitempty"`
	OutputHash   string         `json:"output_hash"`
	Extra        map[string]any `json:"extra,omitempty"`
}
type Backend interface {
	Prepare(context.Context, profile.Candidate) (map[string]any, error)
	Run(context.Context, int) (Measurement, error)
	Close(context.Context) error
}
type Client struct {
	Base, Token string
	HTTP        *http.Client
}

func NewClient(base string) (*Client, error) {
	u, e := url.Parse(base)
	if e != nil {
		return nil, e
	}
	if (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return nil, fmt.Errorf("invalid endpoint")
	}
	// Redirecting requests can leak a bearer token and invalidate local measurements.
	return &Client{Base: strings.TrimRight(base, "/"), Token: os.Getenv("INFERCTL_API_TOKEN"), HTTP: &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}, nil
}
func (c *Client) Request(ctx context.Context, method, path string, body any) (*http.Response, error) {
	var r io.Reader
	if body != nil {
		b, e := json.Marshal(body)
		if e != nil {
			return nil, e
		}
		r = bytes.NewReader(b)
	}
	req, e := http.NewRequestWithContext(ctx, method, c.Base+path, r)
	if e != nil {
		return nil, e
	}
	req.Header.Set("Content-Type", "application/json")
	if c.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.Token)
	}
	res, e := c.HTTP.Do(req)
	if e != nil {
		return nil, e
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		defer res.Body.Close()
		b, _ := io.ReadAll(io.LimitReader(res.Body, 2048))
		return nil, fmt.Errorf("%s %s: HTTP %d: %s", method, path, res.StatusCode, b)
	}
	return res, nil
}
func (c *Client) JSON(ctx context.Context, method, path string, body, out any) error {
	r, e := c.Request(ctx, method, path, body)
	if e != nil {
		return e
	}
	defer r.Body.Close()
	if out == nil {
		_, e = io.Copy(io.Discard, io.LimitReader(r.Body, 1<<20))
		return e
	}
	return json.NewDecoder(io.LimitReader(r.Body, 32<<20)).Decode(out)
}
func New(c profile.Config) (Backend, error) {
	h, e := NewClient(c.URL)
	if e != nil {
		return nil, e
	}
	switch c.Backend {
	case "lmstudio":
		return &LMStudio{Client: h, Config: c}, nil
	case "llamacpp":
		return &LlamaCPP{Client: h, Config: c}, nil
	case "comfyui":
		return NewComfy(h, c)
	}
	return nil, fmt.Errorf("unknown backend")
}
