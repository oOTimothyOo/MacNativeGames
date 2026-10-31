#!/usr/bin/env python3
"""Assemble and sign the Cocoa app from built binaries; game content never enters this bundle."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
checkout = ROOT.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binaries', type=Path, default=checkout / 'out/macos-arm64/Release',
                    help='directory with NativePlay and np-render-icon, built from the repository CMakeLists.txt')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--work-dir', type=Path, required=True)
args = parser.parse_args()
os.umask(0o077)
binaries = args.binaries.expanduser().resolve()
output, work = args.output.expanduser().resolve(), args.work_dir.expanduser().resolve()
if output.suffix != '.app' or output.exists():
    parser.error('choose a new .app output; existing apps are never replaced')
if any(p == checkout or checkout in p.parents for p in (output, work)):
    parser.error('keep generated apps and work outside the checkout')
for name in ('NativePlay', 'np-render-icon'):
    if not (binaries / name).is_file():
        parser.error(f'{binaries / name} is missing; build the project first (see README.md)')
partial = output.with_name(output.stem + '.partial.app')
if partial.exists():
    parser.error('a partial app already exists; inspect it first')
macos, resources = partial / 'Contents/MacOS', partial / 'Contents/Resources'
macos.mkdir(parents=True, mode=0o700)
resources.mkdir(mode=0o700)
work.mkdir(parents=True, exist_ok=True, mode=0o700)
shutil.copy2(binaries / 'NativePlay', macos / 'NativePlay')
icon = work / 'icon.png'
subprocess.run([str(binaries / 'np-render-icon'), str(icon)], check=True)
iconset = work / 'NativePlay.iconset'
iconset.mkdir(exist_ok=True)
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        filename = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
        subprocess.run(['sips', '-z', str(size * scale), str(size * scale), str(icon),
                        '--out', str(iconset / filename)], check=True, stdout=subprocess.DEVNULL)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'NativePlay.icns')], check=True)
with (partial / 'Contents/Info.plist').open('wb') as stream:
    plistlib.dump({'CFBundleExecutable': 'NativePlay', 'CFBundleIdentifier': 'org.macnativegames.native-play',
        'CFBundleName': 'Native Play', 'CFBundleDisplayName': 'Native Play',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.3.0', 'CFBundleVersion': '4',
        'CFBundleIconFile': 'NativePlay', 'LSMinimumSystemVersion': '26.0', 'NSHighResolutionCapable': True,
        'LSApplicationCategoryType': 'public.app-category.utilities', 'LSSupportsGameMode': False,
        'GCSupportsGameMode': False}, stream)
subprocess.run(['codesign', '--force', '--sign', '-', str(partial)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(partial)], check=True)
partial.rename(output)
print(f'Built and verified {output}')
