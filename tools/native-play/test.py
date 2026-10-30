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
    '-framework', 'Foundation', '-o', str(binary)], check=True)
subprocess.run([str(binary), str(work / 'synthetic-state')], check=True, timeout=60)
if args.app:
    fixture = work / 'Synthetic.app'
    executable = fixture / 'Contents/MacOS/Jamboree'
    game = fixture / 'Contents/Resources/game'
    executable.parent.mkdir(parents=True)
    game.mkdir(parents=True)
    subprocess.run(['clang', '-arch', 'arm64', '-mmacosx-version-min=26.0', '-O2', '-Wall', '-Wextra',
                    '-Werror', str(ROOT / 'fixture.c'), '-o', str(executable)], check=True)
    shutil.copy2(executable, game / 'dmhost')
    subprocess.run(['codesign', '--force', '--sign', '-', str(game / 'dmhost')], check=True)
    (game / 'build-info.json').write_text(json.dumps({'game': {'title_id': '0100965017338000', 'version': 'synthetic'},
        'host_sha256': hashlib.sha256((game / 'dmhost').read_bytes()).hexdigest(), 'chain': 'synthetic', 'language': 'en-US'}))
    with (fixture / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleExecutable': 'Jamboree', 'CFBundleIdentifier': 'org.macnativegames.native-play.fixture',
                      'CFBundlePackageType': 'APPL', 'LSMinimumSystemVersion': '26.0'}, stream)
    subprocess.run(['codesign', '--force', '--sign', '-', str(fixture)], check=True)
    subprocess.run([str(args.app / 'Contents/MacOS/NativePlay'), '--launch-check', str(fixture)], check=True, timeout=30)
    subprocess.run([str(args.app / 'Contents/MacOS/NativePlay'), '--ui-test', '--ui-snapshot',
                    str(work / 'synthetic-library.png')], check=True, timeout=30)
