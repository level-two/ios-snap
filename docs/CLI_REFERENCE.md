# CLI Reference

## Subcommands
- `devices` — list iOS simulators.
- `render` — render single scene.
- `batch` — render many scenes from YAML/JSON.
- `list` — list registry scenes (if available).

### `ios-snap batch`
- `--config <file.yml|json>` — required path to batch config (relative paths resolve from config directory).
- `--continue-on-error` — continue processing remaining variants after a failure; exit code reflects first failure.
- Reads schema documented in `docs/BATCH_CONFIG.md` (scenes with variants, optional `global` defaults).
- Each variant merges `global` defaults ⟶ scene defaults ⟶ variant overrides before invoking the render pipeline.
- Example:
  ```
  ios-snap batch --config Examples/Snapshots.yml
  ios-snap batch --config Examples/Snapshots.yml --continue-on-error
  ```

## SwiftPM Command Plugin
- Invoke `swift package ios-snap <args>` to run the CLI via the bundled command plugin.
- The plugin ensures the `ios-snap` executable is built and forwards `stdout`/`stderr` directly.
- The working directory is the package root, so relative `--out` paths behave like running the binary manually.
- Simulator interactions require additional filesystem permissions; run `swift package --disable-sandbox ios-snap …` (or pass targeted `--allow-reading-from-directory/--allow-writing-to-directory` flags) when invoking `render`, `list`, or `batch`.

## Common Flags
- `--device <name>` or `--udid <sim-udid>`
- `--appearance <light|dark|auto>`
- `--content-size <XS|S|M|L|XL|XXL|AX1..AX5>`
- `--locale <xx-YY>` and optional `--region <REGION>`
- `--orientation <portrait|landscape>`
- `--background <#RRGGBB|clear>`
- `--status-bar 'time=09:41 wifi=3 cellular=4 battery=100 state=charged'`
  - Supported tokens include `time`, `wifi`, `cellular`, `battery`, `state`, `carrier`, `bluetooth`, `data`/`network`, and `style` (ios-snap specific: `lightContent`/`darkContent`).
  - ios-snap renders a synthetic status bar in the runner using these values (the simulator overlay is not captured).
- `--wait <seconds>` (default 0.2)
- `--scale <2|3>`
- `--out <path.png>`
- `--verbose`

## Snippet‑mode
- `--expr '<SwiftUI expression>'`
- `--imports 'ModuleA,ModuleB,SwiftUI'`
- `--snippet <path.swift>` (must define `makeView() -> some View`)

### External Dependencies (Phase K)
- `--workspace '<file.xcworkspace>'` or `--project '<file.xcodeproj>'`
  - Use Xcode to build one or more dependency schemes for `iphonesimulator` and stage artifacts for linking.
- `--dep-scheme '<Name>'` (repeatable)
  - Build the given scheme(s) in the provided workspace/project before building the Runner; links as `-framework <Product>` when applicable.
  - `Examples/ExternalDeps/README.md` includes a minimal framework project you can try locally.
- `--package '<path>'` + `--product '<Name>'` (repeatable)
  - Build SwiftPM products using `xcodebuild -package-path <path>` for `iphonesimulator` and stage the outputs.
  - See `Examples/ExternalDeps/README.md` for a runnable package demo.

Notes
- The Runner is not mutated; build settings are injected at compile time (`FRAMEWORK_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, `SWIFT_INCLUDE_PATHS`, `OTHER_LDFLAGS`).
- Frameworks/products must build for `iphonesimulator`; Swift modules may require `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` for interface compatibility.

### Render Dry Run
- `--dry-run` — resolve simulator inputs and exit without building/launching.
- Combine with `--boot` to ensure the target boots before rendering.
- Any `--status-bar` override is applied and cleared during dry-run to validate simctl support.
- Example:
  ```
  ios-snap render --device 'iPhone 15 Pro' \
    --dry-run --boot \
    --status-bar 'time=09:41 wifi=3 cellular=4 battery=100 state=charged'
  ```

## Registry‑mode
- `--scene '<id>'`
- `--app-scheme '<XcodeScheme>'`
- `--workspace '<file.xcworkspace>'`
- `--project '<file.xcodeproj>'`

Notes (Phase K)
- When `--workspace/--project` + `--app-scheme` are provided, ios-snap will build/launch the host app scheme for registry flows instead of the template Runner (planned).

### `ios-snap list`
- Requires `--device <name>` or `--udid <sim-udid>` to select a simulator for launching the registry runner.
- Use `--snippet <file.swift>` to copy registry declarations (must define `makeView()` if used).
- Alternatively, import modules that register scenes with `--imports 'ModuleA,ModuleB'` and let their static initializers call `SnapshotRegistry.register`.
- Example:
  ```
  ios-snap list --device 'iPhone 15' \
    --snippet Examples/Registry/Scenes.swift
  ```

### `ios-snap devices`
- Prints available iOS simulator types (iPhone/iPad) grouped by runtime.
- Each line includes device name, runtime version, UDID, and current state/availability.
- Example:
  ```
  Available iOS simulators:
  - iPhone 16 Pro Max (iOS 18.3) — 1AFA7433-B7C5-4978-8C6A-F8DA691809BD [Shutdown, available]
  ```

## Exit Codes
0 success; 1 args; 2 build; 3 simulator; 4 launch; 5 capture; 6 pull; 7 scene not found.
