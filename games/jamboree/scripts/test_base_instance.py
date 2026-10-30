#!/usr/bin/env python3
"""GPU-written indirect draw regression through the real NVN/Metal replay."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
from build_jamboree import stage, environment, GAME, TITLE

os.umask(0o077)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir', required=True, type=Path)
args = parser.parse_args()
work = args.work_dir.expanduser().resolve()
if work == GAME.parents[1] or GAME.parents[1] in work.parents:
    parser.error('use a private directory outside the checkout')
source = stage(work)
spec = importlib.util.spec_from_file_location('_base_instance_fixture', GAME / 'tests/test_base_instance.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
original = fixture.fixture(existing=True)
before, after = work / 'baseline.metal', work / 'corrected.metal'
before.write_text(original)
after.write_text(fixture.lowering()(original))
env = environment(work)
subprocess.run(['make', '-C', str(source / 'dm/host'), f'GAME={TITLE}', 'game_profile'], env=env, check=True)
subprocess.run(['make', '-C', str(source / 'dm/gfx/tests'), f'GAME={TITLE}', 't_base_instance'], env=env, check=True)
subprocess.run([str(source / 'dm/gfx/tests/t_base_instance'), str(before), str(after)],
               env=dict(env, MTL_DEBUG_LAYER='1', MTL_SHADER_VALIDATION='1'), check=True)
