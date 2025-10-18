# Architecture

## High‑Level Flow
```
CLI → Simulator Manager → Runner Builder → xcodebuild → simctl launch → Runner App
  ↑                                                                                 ↓
  └────────────────────────────── Pull PNG from app Documents via simctl ───────────┘
```

## Components
- CLI (ios-snap): Argument parsing, validation, logging, orchestration, YAML batch.
- Simulator Manager: Resolve/create/boot device; status bar override/clear; locale/appearance.
- Runner Builder:
  - Snippet‑mode: clone `Templates/Runner`, inject `imports` and `expr`/`snippet` into tokens, build.
  - Registry‑mode: build user app exposing `SnapshotRegistry`.
- Dependency Builder (Phase K):
  - Builds external schemes/products for `iphonesimulator` (via Xcode workspace/project or SwiftPM package path).
  - Stages artifacts under the runner workspace and injects build settings for Runner compile/link steps.
- Launcher: `xcodebuild` (iphonesimulator) + `simctl install/launch` with env vars.
- Extractor: `simctl get_app_container …/Documents` → copy PNG to host.
- SnapshotKit: minimal runtime for scene registration; optional `@Snapshot` macro wrapper.
- Command Pipeline (J.5): Sequential operations modeled as commands (prepare workspace, resolve/boot device, apply overrides, build/install/launch, pull artifacts, cleanup). Commands encapsulate I/O, map errors to exit codes, and emit phase-tagged logs.

## Runner Env Vars (Data Contract)
- `SNAP_APPEARANCE=light|dark|auto`
- `SNAP_CONTENT_SIZE=XS|S|M|L|XL|XXL|AX1..AX5`
- `SNAP_SIZE=WIDTHxHEIGHT` (points)
- `SNAP_BACKGROUND=#RRGGBB|clear`
- `SNAP_WAIT=0.2`
- `SNAP_OUT_FILENAME=__snap.png`
- `SNAP_SCENE_ID=locks/default` (registry‑mode)

## Exit Codes
- 0: success
- 1: argument/validation error
- 2: build failed
- 3: simulator unavailable/boot failure
- 4: launch error
- 5: capture/write failed (Runner)
- 6: artifact pull failed
- 7: registry scene not found

## Determinism
- Override status bar; fixed wait; optional fixed background; avoid time‑dependent data.

## Build Settings Injection (Phase K)
- `FRAMEWORK_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, `SWIFT_INCLUDE_PATHS` point to staged outputs.
- `OTHER_LDFLAGS` includes `-framework <Name>` or `-l<Name>` for static libs.
- Avoid mutating `.pbxproj`; pass overrides to `xcodebuild` per build.

## Security Notes
- Token injection is string‑based; do not execute arbitrary shell from snippet input.
- Sanitize imports list and only use as `import` lines; never interpolate into shell.

