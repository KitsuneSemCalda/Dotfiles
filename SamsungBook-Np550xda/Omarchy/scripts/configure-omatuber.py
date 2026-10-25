#!/usr/bin/env python3
"""Enable authenticated OBS access and seed OmaTuber's non-secret preferences."""
import json
import os
from pathlib import Path
import secrets
import tempfile
import uuid


def read(path):
    data = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(data, dict):
        raise ValueError(f'Expected a JSON object: {path}')
    return data


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.omatuber-')
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(data, output, indent=2)
            output.write('\n')
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def configure(config):
    websocket = config / 'obs-studio/plugin_config/obs-websocket/config.json'
    prefs_path = config / 'omatuber/prefs.json'
    obs = read(websocket)
    prefs = read(prefs_path)  # Validate both before changing either.
    port = obs.get('server_port', 4455)
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError('Invalid OBS WebSocket port; existing configuration preserved')
    obs.update(server_enabled=True, auth_required=True, first_load=False, server_port=port)
    if not isinstance(obs.get('server_password'), str) or not obs['server_password']:
        obs['server_password'] = secrets.token_urlsafe(32)
    prefs['obs_port'] = port
    prefs.setdefault('audio_input', str(uuid.uuid5(uuid.NAMESPACE_URL, 'samsung-np550xda/obs/Microphone')))
    prefs.setdefault('scene', 'OmaTuber Live')
    write(websocket, obs)
    write(prefs_path, prefs)
    print('OBS WebSocket enabled with authentication; connect OmaTuber using OBS connection details.')


if __name__ == '__main__':
    configure(Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))))
