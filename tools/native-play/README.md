# Native Play

A small native macOS library for locally built MacNativeGames ports. C/C++ game runtimes, an Objective-C++ bridge to Cocoa/AppKit, Metal graphics, and Python build/test tooling. No web view, JavaScript runtime, Swift runtime or bundled Python interpreter.

The first supported adapter is **Super Mario Party Jamboree**. This launcher does not turn arbitrary Switch archives into playable games. Additional titles need a supported native port, its own validated build, and an adapter for its bundle/save layout.

## Build and launch

Requires Apple Silicon, macOS 26+ and the Xcode Command Line Tools. No additional packages or administrator privileges are needed for this launcher.

```sh
python3 tools/native-play/build.py \
  --output "$HOME/Applications/Native Play.app" \
  --work-dir /private/path/native-play-build
```

Choose a **new** output path; the builder refuses an existing app or partial bundle. Open Native Play from Finder or add it to the Dock, then choose **Add native app…** and select your own built Jamboree `.app`. The game is registered by location rather than copied into the launcher. Keep that game app installed after adding it.

The library has four native pages:

- **Library:** play and open the game's controller setup.
- **Backups:** manual snapshots and restore controls; automatic snapshot before every launch.
- **Performance:** optional per-game Metal HUD and opt-in local timing capture.
- **Controllers:** access to the existing live controller setup, player assignment and button swaps. While playing, use F2 or Command-Shift-C inside the game.

The artwork and icon are simple authored shapes. Game artwork, archives, keys, game code, assets and shaders are not included in the launcher or source changes.

## Privacy and recovery

The game bundle signature, host hash and registered bundle identity are checked before launch. Hash/signature checks establish identity and integrity; they do not certify arbitrary code as safe. Add only a port you trust and have reviewed.

Each game session uses a `sandbox-exec` profile denying networking, restricting writes to the game's state and the private session, and blocking credential stores, private inputs and removable volumes. A content-free helper checks permitted/denied file operations and a denied loopback socket before the game starts. No system security or global environment settings are changed. This still shares the macOS account; it is not a separate user account or a complete isolation boundary.

Native Play stores its library, settings, private backups and optional recordings in `~/Library/Application Support/Native Play/`. Existing Jamboree progress stays in `~/Library/Application Support/Super Mario Party Jamboree/`.

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

Tests cover save/prefs round trips, stale working files, corruption, symlink and traversal rejection, a mid-restore install failure and rollback, snapshot rotation, running-game guards, unsigned bundles, safe launch defaults, numeric timing calculations, and actual native control hit areas. The UI test renders only a synthetic library; it does not launch a game or capture gameplay.

The native game fixes and upstream attribution are recorded in [Jamboree's improvement notes](../../games/jamboree/docs/macos-improvements.md). Game builds, Metal compatibility and two-controller gameplay still require local hardware acceptance.
