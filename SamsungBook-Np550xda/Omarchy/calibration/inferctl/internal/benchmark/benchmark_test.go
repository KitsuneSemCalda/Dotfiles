package benchmark

import (
	"context"
	"errors"
	"inferctl/internal/adapters"
	"inferctl/internal/profile"
	"testing"
	"time"
)

type fake struct {
	calls int
	fail  bool
}

func (f *fake) Prepare(context.Context, profile.Candidate) (map[string]any, error) {
	return map[string]any{"synthetic": true}, nil
}
func (f *fake) Close(context.Context) error { return nil }
func (f *fake) Run(ctx context.Context, i int) (adapters.Measurement, error) {
	f.calls++
	if f.fail {
		return adapters.Measurement{}, errors.New("backend failure")
	}
	return adapters.Measurement{TPS: 10, Seconds: .1, OutputTokens: 10}, nil
}
func TestRepeatedBenchmarkAndFailure(t *testing.T) {
	c := profile.Default("lmstudio")
	c.MinSeconds = 0
	c.Quality.MaxSwap = ^uint64(0)
	c.Quality.HardTemp = 1000
	f := &fake{}
	r := Run(context.Background(), c, c.Candidates[0], f, func(string) {})
	if r.Error != "" || f.calls != 4 || len(r.Runs) != 3 || r.MedianPerformance != 10 {
		t.Fatal(r, f.calls)
	}
	f = &fake{fail: true}
	r = Run(context.Background(), c, c.Candidates[0], f, func(string) {})
	if r.Error == "" || len(r.Runs) > 0 {
		t.Fatal(r)
	}
}
func TestQuantileAndThermalDegradation(t *testing.T) {
	if Quantile([]float64{8, 1, 3, 2}, .5) != 2.5 {
		t.Fatal("median")
	}
	r := Result{}
	for _, n := range []float64{10, 10, 8, 8} {
		r.Runs = append(r.Runs, adapters.Measurement{TPS: n, Seconds: 1})
	}
	Summarize(&r, "lmstudio")
	if r.SustainedRatio != .8 {
		t.Fatal(r.SustainedRatio)
	}
}
func TestManagedBackendRefusesOccupiedPort(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	c := profile.Default("lmstudio")
	c.Command = []string{"/nonexistent"}
	c.URL = "http://127.0.0.1:0"
	if _, e := Start(ctx, c, c.Candidates[0], false, func(string) {}); e == nil {
		t.Fatal("invalid process admitted")
	}
}

func TestMedianBootstrapDeterministicAndBounded(t *testing.T) {
	v := []float64{8, 10, 12}
	a, b := MedianCI(v), MedianCI(v)
	if a != b || a[0] < 8 || a[1] > 12 || a[0] > a[1] {
		t.Fatal(a, b)
	}
	constant := MedianCI([]float64{10, 10, 10})
	if constant != [2]float64{10, 10} {
		t.Fatal(constant)
	}
}
