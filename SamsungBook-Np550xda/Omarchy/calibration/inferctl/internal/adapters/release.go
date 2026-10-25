package adapters

import (
	"context"
	"errors"
	"fmt"
	"inferctl/internal/profile"
)

// Release unloads an exact instance explicitly named in the caller's profile.
// It is the only path allowed to release a model not loaded by the current execution.
func Release(ctx context.Context, r profile.Resident) error {
	if r.Backend != "lmstudio" || r.Instance == "" || r.Model == "" {
		return errors.New("release requires lmstudio, exact model key and instance_id")
	}
	client, e := NewClient(r.URL)
	if e != nil {
		return e
	}
	var listing struct {
		Models []struct {
			Key    string `json:"key"`
			Loaded []struct {
				ID string `json:"id"`
			} `json:"loaded_instances"`
		} `json:"models"`
	}
	if e = client.JSON(ctx, "GET", "/api/v1/models", nil, &listing); e != nil {
		return e
	}
	if listing.Models == nil {
		return errors.New("cannot verify resident model inventory")
	}
	for _, m := range listing.Models {
		for _, i := range m.Loaded {
			if i.ID == r.Instance {
				if m.Key != r.Model {
					return fmt.Errorf("release instance belongs to unexpected model %q", m.Key)
				}
				l := LMStudio{Client: client, Instance: r.Instance}
				return l.Close(ctx)
			}
		}
	}
	return nil
}
