#!/usr/bin/env python3
"""Generate the checked-in OBS profiles and scene collections for both OSes."""
import json
import pathlib
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCENES = ['Gameplay', 'Desktop', 'Programming', 'Project Demo',
          'Camera Fullscreen', 'Starting', 'BRB', 'Ending']


def uid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'samsung-np550xda/obs/' + name))


def scene(name, items=(), transforms=None):
    transforms = transforms or {}
    return {
        'id': 'scene', 'name': name, 'uuid': uid(name),
        'settings': {'id_counter': len(items) + 1, 'custom_size': False,
                     'items': [
                         {'id': i, 'name': source, 'source_uuid': uid(source),
                          'visible': True, 'locked': False,
                          'pos': {'x': transforms.get(source, (0, 0, 1))[0],
                                  'y': transforms.get(source, (0, 0, 1))[1]},
                          'scale': {'x': transforms.get(source, (0, 0, 1))[2],
                                    'y': transforms.get(source, (0, 0, 1))[2]},
                          'align': 5, 'bounds_type': 0}
                         for i, source in enumerate(items, 1)]},
        'mixers': 0, 'volume': 1.0, 'hotkeys': {},
    }


def collection(platform):
    # The portal screen selection is session-specific. The Linux camera node
    # is the built-in webcam of this notebook; Windows needs its local ID.
    camera = {'id': 'pipewire-camera-source' if platform == 'linux' else 'dshow_input',
              'name': 'Camera Device', 'uuid': uid('Camera Device'),
              'settings': {'device_id': 'v4l2_input.pci-0000_00_14.0-usb-0_7_1.0',
                           'format': json.dumps({'encoded': False,
                                                 'video_format': 4,  # SPA_VIDEO_FORMAT_YUY2
                                                 'width': 640, 'height': 480})}
              if platform == 'linux' else {},
              'mixers': 0, 'volume': 1.0, 'hotkeys': {}}
    audio = []
    if platform == 'linux':
        for name, device, tracks in [
            ('Microphone', 'capture_microphone', 17),
            ('Game-System', 'capture_game.monitor', 18),
            ('Discord-Chat', 'capture_chat.monitor', 20),
            ('Music', 'capture_music.monitor', 24),
        ]:
            audio.append({'id': 'pulse_input_capture', 'name': name,
                          'uuid': uid(name), 'settings': {'device_id': device},
                          'mixers': tracks, 'volume': 1.0,
                          'monitoring_type': 0, 'hotkeys': {}})
    monitor = {'id': 'pipewire-desktop-capture-source' if platform == 'linux' else 'monitor_capture',
               'name': 'Monitor Device', 'uuid': uid('Monitor Device'),
               'settings': {}, 'mixers': 0, 'volume': 1.0, 'hotkeys': {}}
    window = {'id': 'pipewire-window-capture-source' if platform == 'linux' else 'window_capture',
              'name': 'Window Device', 'uuid': uid('Window Device'),
              'settings': {}, 'mixers': 0, 'volume': 1.0, 'hotkeys': {}}
    def color(name, rgb, width, height):
        return {'id': 'color_source', 'name': name, 'uuid': uid(name),
                'settings': {'color': 0xff000000 | int(rgb[4:6] + rgb[2:4] + rgb[0:2], 16),
                             'width': width, 'height': height},
                'mixers': 0, 'volume': 1.0, 'hotkeys': {}}

    def title(name, value, size):
        return {'id': 'text_ft2_source', 'name': name, 'uuid': uid(name),
                'settings': {'text': value,
                             'font': {'face': 'Arial' if platform == 'windows' else 'Lexend',
                                      'size': size, 'flags': 1, 'style': 'Bold'},
                             'color1': 0xffffffff, 'color2': 0xffffffff},
                'mixers': 0, 'volume': 1.0, 'hotkeys': {}}

    slates = [color('Slate Background', '101820', 1920, 1080)]
    slate_text = {
        'Starting': ('INICIANDO EM INSTANTES', 'A transmissão começará em breve'),
        'BRB': ('JÁ VOLTO', 'A transmissão continua em instantes'),
        'Ending': ('TRANSMISSÃO ENCERRADA', 'Obrigado por assistir'),
    }
    if platform == 'linux':
        for name in slate_text:
            slates.append({'id': 'image_source', 'name': name + ' Slate',
                           'uuid': uid(name + ' Slate'),
                           'settings': {'file': str(pathlib.Path.home() / '.local/state/obs-theme-slates' /
                                                    (name.lower() + '.png')),
                                        'unload': False},
                           'mixers': 0, 'volume': 1.0, 'hotkeys': {}})
    else:
        slates.append(color('Slate Accent', '44d7c2', 1100, 6))
        for name, (heading, subtitle) in slate_text.items():
            slates.extend((title(name + ' Title', heading, 74),
                           title(name + ' Subtitle', subtitle, 38)))

    sources = [camera, monitor, window, *audio, *slates,
               scene('Capture Monitor', ('Monitor Device',)),
               scene('Capture Window', ('Window Device',)),
               scene('Camera PiP', ('Camera Device',),
                     {'Camera Device': (1560, 800, 0.5)}),
               scene('Audio Buses', tuple(source['name'] for source in audio))]
    recipes = {
        # OBS stores scene items back-to-front; the last video item is on top.
        'Gameplay': ('Capture Monitor', 'Camera PiP', 'Audio Buses'),
        'Desktop': ('Capture Monitor', 'Audio Buses'),
        'Programming': ('Capture Window', 'Camera PiP', 'Audio Buses'),
        'Project Demo': ('Capture Window', 'Camera PiP', 'Audio Buses'),
        'Camera Fullscreen': ('Slate Background', 'Camera Device', 'Audio Buses'),
    }
    for name in slate_text:
        recipes[name] = (('Audio Buses', name + ' Slate') if platform == 'linux'
                         else ('Slate Background', 'Audio Buses', 'Slate Accent',
                               name + ' Subtitle', name + ' Title'))
    transforms = {
        'Camera Fullscreen': {'Camera Device': (240, 0, 2.25)},
        **({name: {name + ' Title': (245, 435, 1),
                   name + ' Subtitle': (250, 555, 1),
                   'Slate Accent': (250, 650, 1)} for name in slate_text}
           if platform == 'windows' else {}),
    }
    sources += [scene(name, recipes[name], transforms.get(name)) for name in SCENES]
    return {'name': 'Capture Infrastructure', 'version': 2,
            'current_scene': 'Desktop', 'current_program_scene': 'Desktop',
            'scene_order': [{'name': name} for name in SCENES],
            'sources': sources, 'groups': [], 'transitions': [],
            'current_transition': 'Fade', 'transition_duration': 300,
            'quick_transitions': [], 'modules': {},
            'resolution': {'x': 1920, 'y': 1080}}


def profile(name, width, height, fps, quality, usage):
    return f'''[General]
Name={name}

[Output]
Mode=Advanced

[Video]
BaseCX=1920
BaseCY=1080
OutputCX={width}
OutputCY={height}
FPSType=0
FPSCommon={fps}
AutoRemux=true

[Audio]
SampleRate=48000
ChannelSetup=Stereo
DesktopDevice1=disabled
AuxDevice1=disabled

[AdvOut]
RecType=Standard
Encoder=obs_qsv11_v2
AudioEncoder=ffmpeg_aac
TrackIndex=5
RecFormat2=mkv
RecEncoder=obs_qsv11_v2
RecAudioEncoder=ffmpeg_aac
RecTracks=31
RecUseRescale=false
Track1Name=Microphone
Track2Name=Game-System
Track3Name=Discord-Chat
Track4Name=Music
Track5Name=Final-Mix
Track1Bitrate=160
Track2Bitrate=192
Track3Bitrate=160
Track4Bitrate=192
Track5Bitrate=192
'''


def write(root, platform):
    profiles = {
        'Desktop Development': (1920, 1080, 60, 18, 'TU4'),
        'Light Gameplay': (1920, 1080, 60, 21, 'TU6'),
        'Heavy Gameplay': (1280, 720, 60, 24, 'TU7'),
    }
    for name, args in profiles.items():
        path = root / 'basic/profiles' / name
        path.mkdir(parents=True, exist_ok=True)
        (path / 'basic.ini').write_text(profile(name, *args), encoding='utf-8')
        settings = {'rate_control': 'CQP', '__ver': 2, 'cqp': args[3],
                    'qpi': args[3], 'qpp': args[3], 'qpb': args[3],
                    'target_usage': args[4], 'profile': 'high',
                    'keyint_sec': 2, 'bframes': 2}
        (path / 'recordEncoder.json').write_text(
            json.dumps(settings, indent=2) + '\n', encoding='utf-8')
        stream_settings = {'rate_control': 'CBR', '__ver': 2,
                           'bitrate': 4500 if name == 'Heavy Gameplay' else 6000,
                           'target_usage': 'TU6', 'profile': 'high',
                           'keyint_sec': 2, 'bframes': 2}
        (path / 'streamEncoder.json').write_text(
            json.dumps(stream_settings, indent=2) + '\n', encoding='utf-8')
    path = root / 'basic/scenes/Capture Infrastructure.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(collection(platform), indent=2) + '\n', encoding='utf-8')
    (root / 'user.ini').write_text('''[General]
FirstRun=true

[Basic]
Profile=Desktop Development
ProfileDir=Desktop Development
SceneCollection=Capture Infrastructure
SceneCollectionFile=Capture Infrastructure.json
''', encoding='utf-8')


write(ROOT / 'Omarchy/home/.config/obs-studio', 'linux')
write(ROOT / 'Windows-11/home/obs-studio', 'windows')
