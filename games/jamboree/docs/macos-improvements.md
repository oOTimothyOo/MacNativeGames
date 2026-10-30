# Jamboree macOS improvements in this fork

Based on MacNativeGames `ff63a162b35d8b486b941191785d8e957c1f5df2`. The working game remains experimental; this is a native port using the game's rewritten ARM64 code and a Metal host. It is not a general Switch emulator.

## Rendering and movies

- Backport nxnative [8fa9b2d](https://github.com/seedds/nxnative/commit/8fa9b2d16348e96b9aa0983de0ba880b03881422): use Metal's actual `base_instance` for GPU-generated indirect draws. The old CPU driver word incorrectly selected instance transforms, causing missing board spaces and stretched geometry. A GPU regression writes both indexed and non-indexed indirect records before drawing and checks the result.
- Fix scissor state after pipeline preparation and clamp samplers to the device's supported capability. Keep independent GPU regressions for these cases.
- Use tested partial-subgroup handling for the Metal vertex path.
- Drain the movie decoder's queued pictures and deliver end-of-stream separately, instead of leaving the opening movie waiting indefinitely. No time-based skip or build-ID bypass is used.

## Controllers and UI

- A read-only HID adapter for the two actual Ultimate 2C Wireless Bluetooth controllers (VID/PID `2dc8:301b`) when Apple's GameController framework does not expose them.
- Independent player routing, controller swapping between occupied slots, A/B and X/Y swaps, live input indicators and saved per-player preferences.
- Input testing captures game input until the screen closes and buttons/sticks return to neutral.
- English native controller settings, reachable mouse hit areas and same-directory atomic preferences writes compatible with the runtime sandbox.
- Selected nxnative [137c229](https://github.com/seedds/nxnative/commit/137c2291955a968168a2c23fe34efa49592ef8a6) focus/controller-applet stand-ins, with focused regressions. The upstream branch was not merged wholesale.

## Extraction and private inputs

The extractor checks path containment independently, rejects unsafe relative paths and linked output parents, and has synthetic path regression tests. Existing game-version/hash, translator-file, shader-chain and local LibHac checks remain in place. Local compiler mode is recorded separately from the maintainer's exact compiler environment; new compiler/shader provenance must be validated rather than silently changing build locks.

Keys, archives, extracted game code/assets, shader caches, saves and diagnostic captures belong outside this source checkout. No such material is included in this fork. Build the actual game locally using your own inputs and the original documented entry point.

## Validation and limits

On the M4 Max, the working graphics build passed 44 base-instance GPU checks; all 25,693 shader records translated successfully. The controller revision passed 98 routing checks, 31 controller-UI checks and 9 settings-persistence checks. Synthetic tests complement, rather than replace, gameplay testing. The user reports substantial rendering improvements and working controller configuration. Every board, minigame, multiplayer path, and relative performance versus Eden has not been verified.

Run portable source tests:

```sh
python3 -m unittest discover -s games/jamboree/tests -v
python3 -m unittest discover -s games/jamboree/runtime/tools/tests -v
```

Run native tests on macOS 26+ with a private directory outside the checkout:

```sh
python3 games/jamboree/scripts/test_controllers.py --work-dir /private/path/controller-tests
python3 games/jamboree/scripts/test_controller_ui.py --work-dir /private/path/controller-ui-tests
python3 games/jamboree/scripts/test_movie.py --work-dir /private/path/movie-tests
python3 games/jamboree/scripts/test_gpu.py --work-dir /private/path/gpu-tests
```

The [Native Play launcher](../../../tools/native-play/README.md) adds a Cocoa library and recovery controls without embedding or changing the game.
