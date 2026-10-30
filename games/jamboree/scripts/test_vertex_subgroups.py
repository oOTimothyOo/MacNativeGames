#!/usr/bin/env python3
"""Check physical vertex lanes, divergent masks, atomic compaction and bounds on GPU."""
import argparse
from pathlib import Path
import subprocess
import sys
from build_jamboree import stage, environment, GAME, TITLE

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir', required=True, type=Path)
args = parser.parse_args()
work = args.work_dir.expanduser().resolve()
if work == GAME.parents[1] or GAME.parents[1] in work.parents:
    parser.error('use a private directory outside the checkout')
source = stage(work)
sys.path.insert(0, str(source / 'dm/gfx/tools'))
from dmsh_subgroups import HELPERS
helpers = work / 'subgroup_helpers.metal'
helpers.write_text(HELPERS)
env = environment(work)
subprocess.run(['make', '-C', str(source / 'dm/host'), f'GAME={TITLE}', 'game_profile'], env=env, check=True)
subprocess.run(['make', '-C', str(source / 'dm/gfx/tests'), f'GAME={TITLE}', 't_vertex_subgroups'], env=env, check=True)
subprocess.run([str(source / 'dm/gfx/tests/t_vertex_subgroups'), str(helpers)],
               env=dict(env, MTL_DEBUG_LAYER='1', MTL_SHADER_VALIDATION='1'), check=True)
