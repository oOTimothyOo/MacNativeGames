#!/usr/bin/env python3
"""Build a small Cocoa/Objective-C++ app; game content never enters this bundle."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--work-dir', type=Path, required=True)
args = parser.parse_args()
os.umask(0o077)
output, work = args.output.expanduser().resolve(), args.work_dir.expanduser().resolve()
checkout = ROOT.parents[1]
if output.suffix != '.app' or output.exists():
    parser.error('choose a new .app output; existing apps are never replaced')
if any(p == checkout or checkout in p.parents for p in (output, work)):
    parser.error('keep generated apps and work outside the checkout')
partial = output.with_name(output.stem + '.partial.app')
if partial.exists():
    parser.error('a partial app already exists; inspect it first')
macos, resources = partial / 'Contents/MacOS', partial / 'Contents/Resources'
macos.mkdir(parents=True, mode=0o700)
resources.mkdir(mode=0o700)
work.mkdir(parents=True, exist_ok=True, mode=0o700)
subprocess.run(['clang++', '-std=c++20', '-arch', 'arm64', '-mmacosx-version-min=26.0',
    '-fobjc-arc', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations',
    str(ROOT / 'main.mm'), str(ROOT / 'NPModel.mm'), '-framework', 'Cocoa',
    '-framework', 'UniformTypeIdentifiers', '-o', str(macos / 'NativePlay')], check=True)
icon = work / 'icon.png'
subprocess.run([str(macos / 'NativePlay'), '--render-icon', str(icon)], check=True)
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
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
        'CFBundleIconFile': 'NativePlay', 'LSMinimumSystemVersion': '26.0', 'NSHighResolutionCapable': True,
        'LSApplicationCategoryType': 'public.app-category.games'}, stream)
subprocess.run(['codesign', '--force', '--sign', '-', str(partial)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(partial)], check=True)
partial.rename(output)
print(f'Built and verified {output}')
