# Intel acceleration and model storage

The SamsungBook NP550XDA has an Intel i5-1135G7 with Tiger Lake Iris Xe.
A normal `perl omarchy.pl` installation (including `--all`) installs these
packages before copying the GPU diagnostic helper:

- Graphics: `mesa`, `vulkan-intel`, `vulkan-icd-loader`, `vulkan-tools`.
- Compute: `intel-compute-runtime`, `level-zero-loader`, `clinfo`.
- Video: `intel-media-driver`, `libva-utils`, `intel-gpu-tools`, `ffmpeg`.
- Helpers: `python`.

The installed `check-ai-acceleration` command checks user access to a DRM render
node, an Intel Vulkan GPU, an OpenCL GPU, a Level Zero GPU and VA-API profiles.
It returns a failure if an API is unavailable. A software renderer or an empty
OpenCL platform list does not count as successful hardware discovery. It does
not change device permissions, install Python packages globally, restart apps
or claim inference performance. `--dry-run`, restore and alternate `--target`
installations do not run hardware probes. Backup-only installations are exempt.

These APIs are application prerequisites. LM Studio or llama.cpp still needs a
compatible GPU runtime selected. Vulkan cannot accelerate an ordinary PyTorch
CPU build. The ComfyUI CPU Docker image deliberately remains a CPU installation;
Tiger Lake Iris Xe is absent from PyTorch's current list of validated XPU client
GPUs. Installing CUDA, ROCm or switching to an XPU wheel is not a supported fix
for this laptop. A different application backend requires separate testing.

Upstream references:

- [Intel compute runtime supported platforms](https://github.com/intel/compute-runtime#supported-platforms)
- [PyTorch Intel GPU requirements](https://docs.pytorch.org/docs/2.14/notes/get_start_xpu.html#hardware-prerequisite)

## Shared model storage

The normal installer also runs `setup-ai-models`. Model weights live outside Git
under `~/.ai/models/lmstudio` and `~/.ai/models/comfyui`. The traditional paths
`~/.lmstudio/models` and `~/.local/share/inferctl/comfyui/models` are symlinks to
those directories. Each application keeps its expected internal directory
structure. Existing directories are moved, not copied; repeated execution is
safe. Conflicting destinations and unexpected links stop migration before any
data moves. The command can be run manually after installation.
