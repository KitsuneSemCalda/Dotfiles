package profile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestStrictProfilesAndAtomicSave(t *testing.T) {
	p := filepath.Join(t.TempDir(), "profile.json")
	c := Default("lmstudio")
	c.Model = "model"
	if e := Save(p, c); e != nil {
		t.Fatal(e)
	}
	loaded, e := Load(p)
	if e != nil || loaded.Validate() != nil || Hash(c) != Hash(loaded) {
		t.Fatal(e)
	}
	if e = os.WriteFile(p, []byte(`{"version":1,"typo":true}`), 0600); e != nil {
		t.Fatal(e)
	}
	if _, e = Load(p); e == nil {
		t.Fatal("unknown config accepted")
	}
	c.Quality.MinRatio = 0
	if c.Validate() == nil {
		t.Fatal("invalid floor accepted")
	}
}
