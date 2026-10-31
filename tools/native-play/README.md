# Native Play

A small native macOS library for locally built MacNativeGames ports. C/C++ game runtimes, an Objective-C++ bridge to Cocoa/AppKit, Metal graphics, and Python build/test tooling. No web view, JavaScript runtime, Swift runtime or bundled Python interpreter.

The library supports multiple validated native apps. **Super Mario Party Jamboree** is the first port tested with a real game on this Mac. Other DM-host ports can opt into the managed-state adapter described below. Other engines need their own adapter. This launcher does not turn arbitrary Switch archives into playable games.

## Build and launch

Requires Apple Silicon, macOS 26+ and the Xcode Command Line Tools. Compile the executables from the repository root with any CMake and Clang, or in a [cppbuild](https://github.com/oOTimothyOo/cpp23-dev-image) container, which puts them in the default location `build.py` and `test.py` use:

```sh
bash ~/git/cpp23-dev-image/scripts/cppbuild.sh Release macos-arm64
# or: cmake -S . -B /private/path/tools -DCMAKE_BUILD_TYPE=Release \
#       -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$PWD/out/macos-arm64/Release" && cmake --build /private/path/tools --parallel
python3 tools/native-play/build.py \
  --output "$HOME/Applications/Native Play.app" \
  --work-dir /private/path/native-play-build
```

Choose a **new** output path; the builder refuses an existing app or partial bundle. Open Native Play from Spotlight or Finder, or keep it in the Dock, then press **+** and select one or more compatible built `.app` bundles. Apps are registered by location without copying their content, so keep each game app installed after adding it. A batch is checked in full before the catalog changes; re-adding an updated path refreshes only that entry.

The library has four native pages:

- **Library:** the selected game's artwork with Play, and a **…** menu for controller setup, Finder, artwork and removal from the library. A searchable shelf of tiles appears from the second game on. Double-click a tile to play.
- **Backups:** snapshots of the selected game, manual backup and restore; an automatic snapshot comes before every launch.
- **Performance:** independent fullscreen, Metal HUD and one-session timing preferences for each installed app.
- **Controllers:** access to a declared live controller setup, player assignment and button swaps. In Jamboree, use F2 or Command-Shift-C while playing.

Long-running work (hashing, backup, restore, launch preparation) runs one job at a time on a background queue, so the window always stays responsive.

## Artwork

Artwork comes from the player's own files. Native Play samples frames from the largest `.mp4` in an installed game's `RomFS`, keeps the most colorful evenly lit one, and caches it privately in `Native Play/Artwork/`. **Choose Artwork…** replaces it with any picture, and **Use Game's Artwork** goes back. A game without a movie shows a plain gradient beside its title.

Nothing is downloaded, and no game artwork, archives, keys, game code, assets or shaders are included in the launcher or this repository. The app icon is made of simple authored shapes.

## Privacy and recovery

The game bundle signature, host hash and registered bundle identity are checked before launch. Hash/signature checks establish identity and integrity; they do not certify arbitrary code as safe. Add only a port you trust and have reviewed.

Each game session uses a `sandbox-exec` profile denying networking, restricting writes to the game's state and the private session, and blocking credential stores, private inputs and removable volumes. A content-free helper checks permitted/denied file operations and a denied loopback socket before the game starts. No system security or global environment settings are changed. This still shares the macOS account; it is not a separate user account or a complete isolation boundary.

Native Play stores its library, settings, private backups and optional recordings in `~/Library/Application Support/Native Play/`. Existing Jamboree progress stays in `~/Library/Application Support/Super Mario Party Jamboree/`. Other managed titles use `Native Play/GameData/<title-id>/`. Saves/backups follow the title ID; separate builds of the same title share progress but have independent launch preferences. Removing an entry deletes neither the installed app nor its saves/backups.

## Managed DM-host adapter

A compatible signed bundle provides `Contents/Resources/game/build-info.json` with a 16-digit hexadecimal `game.title_id`, `game.version`, the signed runtime's `host_sha256`, and:

```json
{
  "host_executable": "Contents/MacOS/GameHost",
  "native_play": {
    "adapter": "dmhost-v2",
    "managed_state": true,
    "sandbox_entry": "sandbox-exec-v1"
  },
  "controller_setup": true
}
```

The primary executable comes from `Info.plist`'s `CFBundleExecutable`. It must honor the supplied `DM_STATE_DIR`, `DM_SAVE` and `DM_TEMP` without redirecting writes into another title's state. The runtime location is allowlisted to `Contents/MacOS/GameHost` or the legacy `Contents/Resources/game/dmhost`. Jamboree's previous layout remains supported. `controller_setup` is optional and must only be declared when `DM_CONTROLLER_SETUP` is implemented. The example is an adapter contract, not evidence that another game is playable.

`sandbox_entry` is optional and declares an additional launch contract: the primary executable accepts `DM_NATIVE_PLAY_POLICY`, checks that it names a private regular file owned by the current user, then replaces itself with `/usr/bin/sandbox-exec -f <policy> <runtime> …`. If applying that policy fails, the game must not start. This permits a normal Launch Services app launch while retaining the restriction profile. Native Play validates the policy with its harmless helper before starting the app. Ports without this explicit capability keep the direct restricted child-process path.

## macOS Game Mode

New Jamboree packages declare Apple's `LSSupportsGameMode` flag and keep the actual runtime in `Contents/MacOS/GameHost`. Native Play opens this compatible package through Launch Services, and its C entry point applies the restriction profile before starting the runtime, keeping the PID and macOS app association. Game resources remain in `Contents/Resources/game/`.

**A launcher must not `exec` during the first moments after launch.** macOS's `gamepolicyd` identifies a new app a few milliseconds in. An `exec` landing in that window is logged as "Game exited via exit event" while the process keeps running, and the daemon never evaluates it again, so Game Mode stays off for the whole session. Bundle identifiers, categories and the restriction profile are not the cause: a bundle with correct metadata hits this race. Jamboree's launcher therefore waits 250 ms before its `exec`, about ten times the measured window. Because this affects only the launcher, the game's runtime and shaders do not change.

To see macOS's decision directly, instead of reading the HUD:

```sh
/usr/bin/log show --last 5m --info --style compact --predicate 'subsystem == "com.apple.gamepolicyd"'
```

A healthy launch shows `Found game`, `Full screen gaming session is now active`, then `Game mode status is now on`. The game must be in native macOS full screen, and macOS remembers a per-game disabled preference. See [Apple's Game Mode instructions](https://support.apple.com/en-euro/105118) and [the bundle flag documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsgamemode). The library itself is a utility and does not request Game Mode.

Launch Services reports when its app terminates but does not provide this launcher with the game's exit status. Those session records use `status: -1` and `exit_status_known: false`; they must not be interpreted as either a confirmed clean exit or a crash. Direct child launches still record their actual exit status. Process-exit notifications finish recordings without background polling or an additional persistent helper.

Snapshots include `save/`, `save.work/` and `controller-layout.txt`; SHA-256 hashes are verified. Only the most recent 20 valid completed snapshots are retained. Invalid or incomplete entries are not automatically deleted. Backup and restore refuse a running game, linked state paths, invalid manifests, corrupt files and data exceeding this adapter's limit.

A restore stages and verifies the selected snapshot, backs up the current state, then swaps state components with rollback on a filesystem failure. A crash or power loss during this multi-component filesystem operation may require recovery from the pre-restore snapshot/retained transaction; it is not an atomic filesystem snapshot.

Normal play skips the continuous frame TSV and boot profiling used during development. The optional [Metal HUD](https://developer.apple.com/videos/play/tech-talks/110339/) is enabled only in that game's launch environment. Timing capture writes numeric frame/GPU timings locally; its summary includes loading and transitions. No benchmark scene or improvement is inferred from those mixed-session numbers.

Timing capture is a one-session option and resets after launching. Completed sessions retain up to 20 summaries and at most 3 raw recordings totaling 256 MB; oversized raw recordings are discarded after summarizing. A running opt-in recording can temporarily exceed that budget. Completed-session temporary files are removed. No background polling or recording runs while the library is idle.

## Tests

All test state is synthetic and kept outside the source checkout:

```sh
python3 tools/native-play/test.py \
  --work-dir /private/path/fresh-native-play-tests \
  --app "$HOME/Applications/Native Play.app"
```

Tests cover multi-app import and independent identity checks, isolated progress/preferences, cross-game restore rejection, non-destructive removal, save/prefs round trips, corruption, malformed catalog values, links/traversal, mid-restore failure/rollback, retention, running-game guards, unsigned bundles, a file added after signing, safe launch defaults and numeric timing calculations. Signed synthetic apps exercise both runtime layouts under the real sandbox. A third fixture exercises Launch Services, the actual Jamboree C entry point and the restriction tool together; it verifies its running bundle identity and writes a success receipt only after the file/network restrictions pass. An end-to-end check adds a signed synthetic game and plays it through the app's own Add and Play code. UI checks drive the real window at three sizes with zero, one and three synthetic games, including the sidebar, search, per-game preferences, artwork, menus and background work; no gameplay is captured.

`--game-mode RUNS` also launches a synthetic full-screen Metal game through the real launcher chain that many times and fails unless macOS's own log reports Game Mode on for every run. It takes over the screen for a few seconds per run, so it is opt-in and not part of CI. Removing the launcher's wait makes this check fail.

Jamboree's packaging suite additionally checks managed state, language and rejection of a public policy file after the real C launcher hands off.

The native game fixes and upstream attribution are recorded in [Jamboree's improvement notes](../../games/jamboree/docs/macos-improvements.md). Game builds, Metal compatibility and two-controller gameplay still require local hardware acceptance.
