#!/usr/bin/env python3
"""Exercise the English controller setup using synthetic devices only."""
import argparse
import os
from pathlib import Path
import subprocess
from build_jamboree import GAME

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir', type=Path, required=True)
args = parser.parse_args()
work = args.work_dir.expanduser().resolve()
if work == GAME.parents[1] or GAME.parents[1] in work.parents:
    parser.error('use a private directory outside the checkout')
work.mkdir(parents=True, exist_ok=True)
binary = work / 'controllers-preview'
subprocess.run(['clang', '-arch', 'arm64', '-mmacosx-version-min=26.0', '-O1', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
    str(GAME / 'tests/controllers_preview.m'), str(GAME / 'runtime/host/front_controllers.m'),
    '-framework', 'Cocoa', '-framework', 'QuartzCore', '-o', str(binary)], check=True)
subprocess.run([str(binary), '--self-test'], env=dict(os.environ, DM_LANG='en-US'), timeout=25, check=True)
settings = work / 'controller-settings'
subprocess.run(['clang', '-arch', 'arm64', '-mmacosx-version-min=26.0', '-O1', '-Wall', '-Wextra', '-Werror',
    str(GAME / 'tests/controller_settings.c'), '-o', str(settings)], check=True)
subprocess.run([str(settings), str(work)], check=True)
