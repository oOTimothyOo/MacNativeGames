#!/usr/bin/env python3
"""Run content-free native backend, restore, and actual AppKit hit-area tests."""
import argparse
import os
from pathlib import Path
import subprocess
import hashlib
import json
import plistlib
import shutil

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir', required=True, type=Path)
parser.add_argument('--app', type=Path)
args = parser.parse_args()
os.umask(0o077)
work = args.work_dir.expanduser().resolve()
if work == ROOT.parents[1] or ROOT.parents[1] in work.parents:
    parser.error('use a fresh private work directory outside the checkout')
work.mkdir(parents=True, exist_ok=True)
binary = work / 'backend-tests'
subprocess.run(['clang++', '-std=c++20', '-arch', 'arm64', '-mmacosx-version-min=26.0', '-fobjc-arc',
    '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations',
    '-fsanitize=undefined', '-fno-sanitize-recover=all', str(ROOT / 'tests.mm'), str(ROOT / 'NPModel.mm'),
    '-framework', 'Cocoa', '-o', str(binary)], check=True)
subprocess.run([str(binary), str(work / 'synthetic-state')], check=True, timeout=60)
if args.app:
    for name, identifier, entry, host_path in (
        ('Legacy', '0100965017338000', 'Jamboree', 'Contents/Resources/game/dmhost'),
        ('Managed', '0100000000000001', 'Fixture', 'Contents/MacOS/GameHost'),
        ('LaunchServices', '0100000000000002', 'Jamboree', 'Contents/MacOS/GameHost'),
    ):
        fixture = work / f'{name}.app'
        executable = fixture / f'Contents/MacOS/{entry}'
        game, host = fixture / 'Contents/Resources/game', fixture / host_path
        executable.parent.mkdir(parents=True)
        game.mkdir(parents=True)
        if name == 'LaunchServices':
            subprocess.run(['clang', '-arch', 'arm64', '-mmacosx-version-min=26.0', '-O2', '-Wall', '-Wextra',
                            '-Werror', str(ROOT.parents[1] / 'games/jamboree/app/launcher.c'), '-o', str(executable)], check=True)
            subprocess.run(['clang++', '-arch', 'arm64', '-mmacosx-version-min=26.0', '-fobjc-arc', '-O2', '-Wall', '-Wextra',
                            '-Werror', str(ROOT / 'managed_fixture.mm'), '-framework', 'Cocoa', '-o', str(host)], check=True)
        else:
            subprocess.run(['clang', '-arch', 'arm64', '-mmacosx-version-min=26.0', '-O2', '-Wall', '-Wextra',
                            '-Werror', str(ROOT / 'fixture.c'), '-o', str(executable)], check=True)
            shutil.copy2(executable, host)
        subprocess.run(['codesign', '--force', '--sign', '-', str(host)], check=True)
        adapter = {'adapter': 'dmhost-v2', 'managed_state': True}
        if name == 'LaunchServices':
            adapter['sandbox_entry'] = 'sandbox-exec-v1'
        (game / 'build-info.json').write_text(json.dumps({'game': {'title_id': identifier, 'version': 'synthetic'},
            'host_sha256': hashlib.sha256(host.read_bytes()).hexdigest(), 'host_executable': host_path,
            'native_play': adapter, 'chain': 'synthetic', 'language': 'en-US'}))
        with (fixture / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleExecutable': entry, 'CFBundleIdentifier': f'org.macnativegames.fixture.{name.lower()}',
                          'CFBundlePackageType': 'APPL', 'LSMinimumSystemVersion': '26.0'}, stream)
        subprocess.run(['codesign', '--force', '--sign', '-', str(fixture)], check=True)
        subprocess.run([str(args.app / 'Contents/MacOS/NativePlay'), '--launch-check', str(fixture)], check=True, timeout=30)
    subprocess.run([str(args.app / 'Contents/MacOS/NativePlay'), '--ui-test', '--ui-snapshot',
                    str(work / 'synthetic-library.png')], check=True, timeout=30)
