#!/usr/bin/env python3
"""Run the content-free backend, launch-path and AppKit tests from built binaries."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent
checkout = ROOT.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binaries', type=Path, default=checkout / 'out/macos-arm64/Release',
                    help='directory with the executables built from the repository CMakeLists.txt')
parser.add_argument('--work-dir', required=True, type=Path)
parser.add_argument('--app', type=Path, help='a built Native Play.app: also runs the launch-path and UI tests')
parser.add_argument('--game-mode', type=int, default=0, metavar='RUNS',
                    help='also check Game Mode: each run takes over the screen for a few seconds and reads the system log')
args = parser.parse_args()
os.umask(0o077)
binaries = args.binaries.expanduser().resolve()
work = args.work_dir.expanduser().resolve()
if work == checkout or checkout in work.parents:
    parser.error('use a fresh private work directory outside the checkout')
work.mkdir(parents=True, exist_ok=True)


def make_fixture(name, title_id, entry, host_path, adapter, entry_binary, host_binary, game_mode=False):
    """A signed synthetic bundle with the layout and declarations of a real port."""
    fixture = work / f'{name}.app'
    identifier = f'org.macnativegames.fixture.{name.lower()}'
    executable, host, game = fixture / f'Contents/MacOS/{entry}', fixture / host_path, fixture / 'Contents/Resources/game'
    executable.parent.mkdir(parents=True)
    game.mkdir(parents=True)
    shutil.copy2(binaries / entry_binary, executable)
    shutil.copy2(binaries / host_binary, host)
    subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', identifier, str(host)], check=True)
    (game / 'build-info.json').write_text(json.dumps({'game': {'title_id': title_id, 'version': 'synthetic'},
        'host_sha256': hashlib.sha256(host.read_bytes()).hexdigest(), 'host_executable': host_path,
        'native_play': adapter, 'chain': 'synthetic', 'language': 'en-US'}))
    info = {'CFBundleExecutable': entry, 'CFBundleIdentifier': identifier, 'CFBundlePackageType': 'APPL',
            'LSMinimumSystemVersion': '26.0', 'NSHighResolutionCapable': True}
    if game_mode:
        info |= {'LSApplicationCategoryType': 'public.app-category.games', 'LSSupportsGameMode': True, 'GCSupportsGameMode': True}
    with (fixture / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump(info, stream)
    subprocess.run(['codesign', '--force', '--sign', '-', str(fixture)], check=True)
    return fixture


def game_mode_verdict(start):
    """What macOS's Game Mode daemon decided since `start`, from its own log."""
    log = subprocess.run(['/usr/bin/log', 'show', '--start', start, '--info', '--style', 'compact',
                          '--predicate', 'subsystem == "com.apple.gamepolicyd"'],
                         capture_output=True, text=True, check=True).stdout
    if 'Game mode status is now on' in log:
        return 'on'
    return 'identified-but-off' if 'Found game' in log else 'not-identified'


subprocess.run([str(binaries / 'np-backend-tests'), str(work / 'synthetic-state')], check=True, timeout=120)
if args.app:
    probe = str(args.app.expanduser().resolve() / 'Contents/MacOS/NativePlay')
    direct = {'adapter': 'dmhost-v2', 'managed_state': True}
    launch_services = direct | {'sandbox_entry': 'sandbox-exec-v1'}
    for fixture in (
        make_fixture('Legacy', '0100965017338000', 'Jamboree', 'Contents/Resources/game/dmhost', direct, 'np-fixture', 'np-fixture'),
        make_fixture('Managed', '0100000000000001', 'Fixture', 'Contents/MacOS/GameHost', direct, 'np-fixture', 'np-fixture'),
        make_fixture('LaunchServices', '0100000000000002', 'Jamboree', 'Contents/MacOS/GameHost', launch_services, 'jamboree-launcher', 'np-managed-fixture'),
    ):
        subprocess.run([str(binaries / 'np-launch-check'), str(fixture), probe], check=True, timeout=60)
    subprocess.run([str(binaries / 'np-ui-tests'), '--add-and-play', str(fixture)], check=True, timeout=120)
    subprocess.run([str(binaries / 'np-ui-tests'), '--snapshot', str(work / 'synthetic-library.png')], check=True, timeout=120)
    if args.game_mode:
        fixture = make_fixture('GameMode', '0100000000000003', 'Jamboree', 'Contents/MacOS/GameHost', launch_services,
                               'jamboree-launcher', 'np-game-mode-fixture', game_mode=True)
        verdicts = []
        for _ in range(args.game_mode):
            start = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            subprocess.run([str(binaries / 'np-launch-check'), '--no-receipt', str(fixture), probe], check=True, timeout=60)
            time.sleep(2)
            verdicts.append(game_mode_verdict(start))
        print(f'Game Mode verdicts: {verdicts}')
        if verdicts != ['on'] * len(verdicts):
            raise SystemExit('macOS did not enable Game Mode for every launch')
