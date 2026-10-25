package hardware

import (
	"os"
	"path/filepath"
	"testing"
)

func TestZramLogicalUsageIsNotItsPhysicalMemory(t *testing.T) {
	root := t.TempDir()
	proc := filepath.Join(root, "swaps")
	sys := filepath.Join(root, "sys")
	if err := os.MkdirAll(filepath.Join(sys, "zram0"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(proc, []byte("Filename Type Size Used Priority\n/dev/zram0 partition 1000 800 100\n/swap/swapfile file 1000 10 0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sys, "zram0/mm_stat"), []byte("700000 300000 350000 0"), 0600); err != nil {
		t.Fatal(err)
	}
	ds, err := swapDevices(proc, sys)
	if err != nil || len(ds) != 2 {
		t.Fatal(ds, err)
	}
	z := ds[0]
	if z.Kind != "zram" || z.Used != 800*1024 || z.PhysicalMemory == nil || *z.PhysicalMemory != 350000 || z.CompressedData == nil || *z.CompressedData != 300000 {
		t.Fatal(z)
	}
	if ds[1].Kind == "zram" || ds[1].PhysicalMemory != nil {
		t.Fatal("disk swap treated as compressed RAM")
	}
}
func TestMissingZramMetricsRemainUnknown(t *testing.T) {
	root := t.TempDir()
	p := filepath.Join(root, "swaps")
	_ = os.WriteFile(p, []byte("Filename Type Size Used Priority\n/dev/zram1 partition 10 0 100\n"), 0600)
	ds, err := swapDevices(p, root)
	if err != nil || len(ds) != 1 || ds[0].PhysicalMemory != nil {
		t.Fatal(ds, err)
	}
	if zramName("zram") || zramName("zramx") || !zramName("zram12") {
		t.Fatal("invalid zram name classification")
	}
}
