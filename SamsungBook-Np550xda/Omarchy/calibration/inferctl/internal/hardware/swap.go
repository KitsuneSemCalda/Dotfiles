package hardware

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// ZRAM statistics are bytes from mm_stat, not the logical swap capacity.
type SwapDevice struct {
	Path           string  `json:"path"`
	Type           string  `json:"type"`
	Kind           string  `json:"kind"`
	Size           uint64  `json:"size_bytes"`
	Used           uint64  `json:"used_bytes"`
	Priority       int     `json:"priority"`
	LogicalData    *uint64 `json:"zram_logical_data_bytes,omitempty"`
	CompressedData *uint64 `json:"zram_compressed_data_bytes,omitempty"`
	PhysicalMemory *uint64 `json:"zram_physical_memory_bytes,omitempty"`
	BackingDevice  string  `json:"zram_backing_device,omitempty"`
}

func zramName(name string) bool {
	if !strings.HasPrefix(name, "zram") || len(name) == 4 {
		return false
	}
	for _, c := range name[4:] {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
func swapDevices(procPath, sysBlock string) ([]SwapDevice, error) {
	b, err := os.ReadFile(procPath)
	if err != nil {
		return nil, err
	}
	devices := []SwapDevice{}
	for _, line := range strings.Split(string(b), "\n") {
		f := strings.Fields(line)
		if len(f) == 0 || f[0] == "Filename" {
			continue
		}
		if len(f) != 5 {
			return nil, fmt.Errorf("invalid /proc/swaps row")
		}
		size, e1 := strconv.ParseUint(f[2], 10, 64)
		used, e2 := strconv.ParseUint(f[3], 10, 64)
		priority, e3 := strconv.Atoi(f[4])
		if e1 != nil || e2 != nil || e3 != nil || size > ^uint64(0)/1024 || used > size {
			return nil, fmt.Errorf("invalid swap counters")
		}
		d := SwapDevice{Path: f[0], Type: f[1], Kind: "backing-storage", Size: size * 1024, Used: used * 1024, Priority: priority}
		name := filepath.Base(d.Path)
		if strings.HasPrefix(d.Path, "/dev/") && zramName(name) {
			d.Kind = "zram"
			dir := filepath.Join(sysBlock, name)
			fields := strings.Fields(read(filepath.Join(dir, "mm_stat")))
			values := []**uint64{&d.LogicalData, &d.CompressedData, &d.PhysicalMemory}
			for i, target := range values {
				if i < len(fields) {
					if n, e := strconv.ParseUint(fields[i], 10, 64); e == nil {
						*target = &n
					}
				}
			}
			d.BackingDevice = read(filepath.Join(dir, "backing_dev"))
		}
		devices = append(devices, d)
	}
	return devices, nil
}
