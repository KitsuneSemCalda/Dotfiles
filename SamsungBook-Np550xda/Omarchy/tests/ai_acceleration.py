#!/usr/bin/env python3
"""Reject software-only discovery and verify repeatable model migration."""
import contextlib
import importlib.machinery
import importlib.util
import io
from pathlib import Path
import tempfile
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]

def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace('-', '_'), str(root / 'home/.local/bin' / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module

probe = load('check-ai-acceleration')

def check(vulkan='deviceType = INTEGRATED_GPU\nvendorID = 0x8086', cl='Device Type GPU\nIntel', ze=True, va=True):
    def run(command):
        if command[0] == 'vulkaninfo': return True, vulkan
        if command[0] == 'clinfo': return True, cl
        return va, 'VAEntrypointEncSlice' if va else 'driver initialization failed'
    with patch.object(probe, 'run', side_effect=run), patch.object(probe, 'level_zero', return_value=(ze, 'test')), \
         patch.object(probe.glob, 'glob', return_value=['/dev/dri/renderD128']), patch.object(probe.os, 'access', return_value=True):
        with contextlib.redirect_stdout(io.StringIO()): return probe.check()

assert check() == 0
assert check(vulkan='deviceType = CPU\nvendorID = 0x10005\ndeviceName = llvmpipe') == 1
assert check(cl='Number of platforms 0') == 1
assert check(cl='Intel CPU\nDevice Type CPU') == 1
assert check(ze=False) == 1
assert check(va=False) == 1
models = load('setup-ai-models')
with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
    h = Path(tmp); source = h / '.lmstudio/models/publisher/model/test.gguf'
    source.parent.mkdir(parents=True); source.write_bytes(b'weights')
    models.setup(h); models.setup(h)
    assert source.is_file() and source.read_bytes() == b'weights'
    assert (h / '.ai/models/lmstudio/publisher/model/test.gguf').read_bytes() == b'weights'
    (h / '.local/share/inferctl/comfyui/models').unlink()
    (h / '.local/share/inferctl/comfyui/models').mkdir()
    try: models.setup(h)
    except SystemExit: pass
    else: raise AssertionError('Conflicting directories must not be merged or overwritten')
    assert source.read_bytes() == b'weights'
print('GPU discovery failure cases and model storage migration passed.')
