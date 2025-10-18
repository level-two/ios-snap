# ios-snap

SwiftUI CLI snapshotter that renders views to PNGs via the iOS Simulator — like Xcode Previews, but scriptable, CI-friendly, and deterministic.

## Features
- Two modes:
  - Snippet‑mode: render any SwiftUI expression without touching your app code.
  - Registry‑mode: register named scenes (like Previews) and render by id.
- Control device, light/dark, Dynamic Type, locale, orientation (visual), background, status bar, and wait.
- Status bar overrides are rendered directly in the PNG so the top strip reflects `--status-bar` values.
- YAML batch for matrices.
- Pulls PNGs to host file system; clears simulator status bar overrides.

## Quick Start (Snippet‑mode)
```
# List available simulators
ios-snap devices

# Render a simple view
ios-snap render \
  --expr 'Text("Hello")' \
  --imports 'SwiftUI' \
  --device 'iPhone 15' \
  --out ./screens/hello.png
```

## Install
- Requires macOS, Xcode (with iOS Simulator runtime), SwiftPM.
- Build from source:
```
git clone https://example.com/ios-snap.git
cd ios-snap
swift build -c release
cp .build/release/ios-snap /usr/local/bin/
```
Or invoke via `swift run ios-snap …` during development.

## SwiftPM Command Plugin
After the package has been built at least once, you can invoke the CLI through the bundled command plugin:
```
swift package ios-snap --help
swift package ios-snap render \
  --expr 'Text("Hello")' \
  --imports 'SwiftUI' \
  --device 'iPhone 15' \
  --out ./screens/plugin-hello.png
```
The plugin forwards arguments to the ios-snap binary and runs from the package root so relative paths resolve just like the standalone executable.
Simulator-driven commands (render, list, batch) require broader filesystem access; invoke the plugin with `swift package --disable-sandbox ios-snap …` (or granular `--allow-reading-from-directory/--allow-writing-to-directory` flags) when you need to touch the Simulator. Alternatively, run the compiled `ios-snap` binary directly.

## Modes Overview
- Snippet‑mode (zero integration):
```
ios-snap render \
  --expr 'LocksScreen(viewModel: .preview)' \
  --imports 'MyAppUI,MyAppMocks' \
  --device 'iPhone 15 Pro' \
  --appearance dark \
  --status-bar 'time=09:41 wifi=3 cellular=4 battery=100' \
  --out ./screens/locks-dark.png
```

- Registry‑mode (minimal integration):
```swift
// SnapshotScenes.swift in your UI module
import SwiftUI
import SnapshotKit
import MyAppUI
import MyAppMocks

@Snapshot("locks/default", size: .iPhone15Pro)
var locksDefault: some View { LocksScreen(viewModel: .preview) }
```

```
ios-snap list
ios-snap render --scene 'locks/default' --device 'iPhone 15' --out ./screens/locks-default.png
```

```
# Demo registry scenes shipped with this repo
ios-snap list --device 'iPhone 15' \
  --snippet Examples/Registry/Scenes.swift

ios-snap render --scene 'demo/hello' --device 'iPhone 15' \
  --snippet Examples/Registry/Scenes.swift \
  --out ./screens/demo-hello.png
```

Contents of `Examples/Registry/Scenes.swift` register scenes via the SnapshotRegistry API:

```swift
import SwiftUI
#if canImport(SnapshotKit)
import SnapshotKit
#endif

private func registerSnapshots() {
    SnapshotRegistry.register("demo/hello", size: .iPhone15Pro) { DemoHelloView() }
    SnapshotRegistry.register("demo/error", size: .iPhoneSE3) { DemoErrorView() }
}

func makeView() -> some View {
    registerSnapshots()
    return EmptyView()
}
```

## Batch Mode
 - Define scenes and variants in a YAML/JSON file (see `docs/BATCH_CONFIG.md` for schema).
- Relative paths inside the config resolve against the config file directory.
- Run all variants:
```
ios-snap batch --config Examples/Snapshots.yml
```
- Keep going after failures (exit code reflects first failure):
```
ios-snap batch --config Examples/Snapshots.yml --continue-on-error
```
- The bundled `Examples/Snapshots.yml` generates snippet and registry screenshots into `screens/`.

## Self-Test
- Run `Scripts/selftest.sh` on a macOS host with Xcode and simulator runtimes installed to execute the verification matrix from `SPEC.md`.
- The script builds `ios-snap` in release mode (unless `IOS_SNAP_BIN` is set) and writes outputs to `screens/selftest/` alongside batch artefacts in `screens/`.
- Override defaults with `SELFTEST_DEVICE` (target simulator name) or `SELFTEST_OUT_DIR` (output folder) as needed.
- Inspect the console output to confirm dark mode, Dynamic Type, status bar overrides, batch runs, and registry renders succeed.

## Repository Layout
```
Package.swift
Sources/
  ios-snap/            # CLI executable
  SnapshotKit/         # Registry runtime
Templates/
  Runner/              # Minimal SwiftUI runner Xcode project
Examples/
  Registry/            # Sample registry declarations
  ExternalDeps/        # Framework + SwiftPM demos for dependency flags
  Snapshots.yml        # Batch example
Scripts/
  selftest.sh          # End‑to‑end checks
docs/
  README.md            # Documentation index and guides
```

## Documentation
- See `docs/README.md` for the full index.
- Quick links:
  - `docs/ARCHITECTURE.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/BATCH_CONFIG.md`
  - `docs/CODING_STYLE.md`
  - `docs/TESTING.md`
  - `docs/CI.md`
  - `docs/TROUBLESHOOTING.md`
  - `docs/CONTRIBUTING.md`
  - Root `AGENTS.md` for agent workflow rules

## License
MIT

## External Dependencies (Phase K)
If your views live in a separate module (framework/package), you can direct ios-snap to build/link those dependencies before compiling the Runner:

Snippet example with a workspace scheme:
```
ios-snap render \
  --snippet Snapshots/CheckoutFlow.swift \
  --workspace MyApp.xcworkspace \
  --dep-scheme CheckoutUI \
  --device 'iPhone 15' \
  --out screens/checkout.png
```

SwiftPM package example:
```
ios-snap render \
  --snippet Snapshots/CheckoutFlow.swift \
  --package ../Checkout \
  --product CheckoutUI \
  --device 'iPhone 15' \
  --out screens/checkout.png
```

See `Examples/ExternalDeps/README.md` for ready-to-run demos that ship with the repository (framework + SwiftPM).

Notes
- Products must build for `iphonesimulator`; for Swift modules, enabling `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` is recommended.
- The Runner project is not modified; ios-snap injects search paths and linker flags at build time.
