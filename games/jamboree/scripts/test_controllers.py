#!/usr/bin/env python3
"""Test controller mapping and independent player input without game data."""
import argparse
from pathlib import Path
import subprocess
from build_jamboree import stage, environment, GAME, TITLE

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir', required=True, type=Path)
args = parser.parse_args()
work = args.work_dir.expanduser().resolve()
if work == GAME.parents[1] or GAME.parents[1] in work.parents:
    parser.error('use a private directory outside the checkout')
source = stage(work)
env = environment(work)
subprocess.run(['make', '-C', str(source / 'dm/host'), f'GAME={TITLE}', 'game_profile'], env=env, check=True)
subprocess.run(['make', '-C', str(source / 'dm/host/tests'), f'GAME={TITLE}', 'hid'], env=env, check=True)
