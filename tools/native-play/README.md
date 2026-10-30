# Native Play

A small native macOS library for locally built MacNativeGames ports. C/C++ game runtimes, an Objective-C++ bridge to Cocoa/AppKit, Metal graphics, and Python build/test tooling. No web view, JavaScript runtime, Swift runtime or bundled Python interpreter.

The library supports multiple validated native apps. **Super Mario Party Jamboree** is the first port tested with a real game on this Mac. Other DM-host ports can opt into the managed-state adapter described below. Other engines need their own adapter. This launcher does not turn arbitrary Switch archives into playable games.

## Build and launch

Requires Apple Silicon, macOS 26+ and the Xcode Command Line Tools. No additional packages or administrator privileges are needed for this launcher.

```sh
python3 tools/native-play/build.py \
  --output "$HOME/Applications/Native Play.app" \
  --work-dir /private/path/native-play-build
```

Choose a **new** output path; the builder refuses an existing app or partial bundle. Open Native Play from Finder or add it to the Dock, then choose **Add native apps…** and select one or more compatible built `.app` bundles. Apps are registered by location without copying their content. Keep each game app installed after adding it. A batch is checked in full before the catalog changes; re-adding an updated path refreshes only that entry.

The library has four native pages:

- **Library:** a responsive searchable grid, selection, Play, Reveal and non-destructive removal from the library.
- **Backups:** a game selector, padded snapshot rows, manual snapshots and restore controls; automatic snapshot before every launch.
- **Performance:** independent fullscreen, Metal HUD and one-session timing preferences for each installed app.
- **Controllers:** a game selector and access to a declared live controller setup, player assignment and button swaps. In Jamboree, use F2 or Command-Shift-C while playing.

The artwork and icon are simple authored shapes. Game artwork, archives, keys, game code, assets and shaders are not included in the launcher or source changes.

## Privacy and recovery

The game bundle signature, host hash and registered bundle identity are checked before launch. Hash/signature checks establish identity and integrity; they do not certify arbitrary code as safe. Add only a port you trust and have reviewed.

Each game session uses a `sandbox-exec` profile denying networking, restricting writes to the game's state and the private session, and blocking credential stores, private inputs and removable volumes. A content-free helper checks permitted/denied file operations and a denied loopback socket before the game starts. No system security or global environment settings are changed. This still shares the macOS account; it is not a separate user account or a complete isolation boundary.

Native Play stores its library, settings, private backups and optional recordings in `~/Library/Application Support/Native Play/`. Existing Jamboree progress stays in `~/Library/Application Support/Super Mario Party Jamboree/`. Other managed titles use `Native Play/GameData/<title-id>/`. Saves/backups follow the title ID; separate builds of the same title share progress but have independent launch preferences. Removing an entry deletes neither the installed app nor its saves/backups.

## Managed DM-host adapter

A compatible signed bundle provides `Contents/Resources/game/build-info.json` with a 16-digit hexadecimal `game.title_id`, `game.version`, the signed runtime's `host_sha256`, and:

```json
{
  "host_executable": "Contents/MacOS/GameHost",
  "native_play": { "adapter": "dmhost-v2", "managed_state": true },
  "controller_setup": true
}
```

The primary executable comes from `Info.plist`'s `CFBundleExecutable`. It must honor the supplied `DM_STATE_DIR`, `DM_SAVE` and `DM_TEMP` without redirecting writes into another title's state. The runtime location is allowlisted to `Contents/MacOS/GameHost` or the legacy `Contents/Resources/game/dmhost`. Jamboree's previous layout remains supported. `controller_setup` is optional and must only be declared when `DM_CONTROLLER_SETUP` is implemented. The example is an adapter contract, not evidence that another game is playable.

## macOS Game Mode

New Jamboree packages declare Apple's `LSSupportsGameMode` flag and keep the actual runtime in `Contents/MacOS/GameHost`. The C entry point hands off to that runtime while retaining the bundle identity that AppKit and macOS use. Game resources remain in `Contents/Resources/game/`; moving the unchanged runtime requires no shader rebuild.

Start the game in native macOS full screen, then use Command-Esc to open the Game Overlay on macOS 26 and check Game Mode. macOS controls activation and remembers a per-game disabled preference; a bundle flag alone does not establish that Game Mode is active. See [Apple's Game Mode instructions](https://support.apple.com/en-euro/105118) and [the bundle flag documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsgamemode). The library itself is a utility and does not request Game Mode.

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

Tests cover multi-app import and independent identity checks, isolated progress/preferences, cross-game restore rejection, non-destructive removal, save/prefs round trips, corruption, links/traversal, mid-restore failure/rollback, retention, running-game guards, unsigned bundles, safe launch defaults, numeric timing calculations, and native hit areas. Signed synthetic apps exercise both runtime layouts under the real sandbox. UI checks render three synthetic catalog entries at three window sizes; no gameplay is captured. Jamboree's packaging suite additionally compiles a content-free runtime and checks its bundle identity and managed state after the real C launcher hands off.

The native game fixes and upstream attribution are recorded in [Jamboree's improvement notes](../../games/jamboree/docs/macos-improvements.md). Game builds, Metal compatibility and two-controller gameplay still require local hardware acceptance.
