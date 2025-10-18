# ios-snap Implementation Plan (Granular & Testable)

This plan turns SPEC.md into a stepwise build with entry/exit criteria and verifiable checks. Follow phases in order; each has a local verification step. All commands assume macOS with Xcode + Simulator available.

## Assumptions
- macOS 14+, Xcode 15/16 with iOS Simulator runtime installed
- SwiftPM available (`swift --version` prints 5.10+)
- `xcrun simctl` available

---

## Phase A — Repo Scaffold
Goal: Create SwiftPM workspace and docs, no functional code.

Tasks
- A1: Create `Package.swift` with targets: `ios-snap` (executable), `SnapshotKit` (library).
- A2: Add dependencies: `ArgumentParser` (CLI), `Yams` (YAML) as needed later.
- A3: Add folders: `Sources/ios-snap`, `Sources/SnapshotKit`, `Templates/Runner`, `Examples`, `Scripts`.
- A4: Add `.gitignore` for `/.build`, `/DerivedData`, `/Temp`, `/screens`.

Done when
- `swift build` succeeds (compiles no-op targets).

Verify
- Run: `swift build` → exit 0

---

## Phase B — CLI Skeleton
Goal: Parse subcommands/flags and print help. No side effects.

Tasks
- B1: Wire `ArgumentParser` entry with subcommands: `devices`, `render`, `batch`, `list`.
- B2: Implement `--verbose` flag on root; consistent logging helper (stdout/stderr separation).
- B3: Add `Shell` helper (argv array, captures stdout/stderr/status).
- B4: Add error type → exit code mapping per docs/ARCHITECTURE.md.

Done when
- `swift run ios-snap --help` renders usage; each subcommand shows help.

Verify
- Run: `swift run ios-snap --help`
- Run: `swift run ios-snap render --help` (and others) → usage prints

---

## Phase C — Devices Command
Goal: List available iOS simulators.

Tasks
- C1: Call `xcrun simctl list --json devices` via Shell.
- C2: Parse JSON; filter available iOS devices (ignore watch/tv, unavailable).
- C3: Pretty-print: name, runtime version, UDID, availability.

Done when
- `ios-snap devices` prints at least one device on a machine with runtimes.

Verify
- Run: `swift run ios-snap devices` → human-readable list

---

## Phase D — Simulator Manager Utilities
Goal: Resolve, create, boot, and wait for device readiness.

Tasks
- D1: Resolve UDID by `--device` name (pick latest iOS runtime); prefer `--udid` when provided.
- D2: Create device if missing: `xcrun simctl create` with best runtime; surface clear errors.
- D3: Boot if needed: `xcrun simctl boot <udid>`; wait until booted (`simctl bootstatus`).
- D4: Implement status bar override/clear helpers.

Done when
- Given a name/udid, functions return a booted UDID or a clear error.

Verify
- Run: `swift run ios-snap devices` (sanity) then call internal `resolve` via `render --dry-run` printing chosen UDID.

---

## Phase E — Runner Template & Injection (Snippet‑mode)
Goal: Build a minimal Runner app that renders RootView and writes PNG.

Tasks
- E1: Add `Templates/Runner` Xcode project with:
  - RunnerApp.swift (reads env, hosts RootView, captures PNG to Documents)
  - RootView.swift with tokens: `//__SNAP_IMPORTS__`, `//__SNAP_EXPR__`
  - Info.plist, bundle id `com.example.Runner`, iOS 17+ deployment
- E2: Implement snippet injection:
  - Copy template to temp workdir
  - If `--snippet` set: copy file into Runner and set expr to `makeView()`
  - Else use `--imports` + `--expr` to replace tokens

Done when
- Template builds for iphonesimulator in isolation.

Verify
- Run: `xcodebuild -project Runner.xcodeproj -scheme Runner -sdk iphonesimulator -configuration Release -quiet` in the copied temp dir → exit 0

---

## Phase F — Render Flow (Build, Install, Launch, Pull)
Goal: End‑to‑end rendering for snippet‑mode.

Tasks
- F1: Build with `xcodebuild -destination id=<UDID>` to produce `.app`.
- F2: Install app: `xcrun simctl install <UDID> <Runner.app>`.
- F3: Apply status bar overrides (if provided).
- F4: Launch with env: `simctl launch --terminate-running-process --console <UDID> com.example.Runner ...ENV...`.
- F5: After app exits, copy PNG from `simctl get_app_container <UDID> com.example.Runner data` → `Documents/__snap.png` to `--out`.
- F6: Clear status bar overrides.

Done when
- A single PNG is written to `--out` for a simple `Text("Hello")` expression.

Verify
- Run: `ios-snap render --expr 'Text("Hello")' --imports 'SwiftUI' --device 'iPhone 15' --out ./screens/hello.png` → file exists and is PNG

---

## Phase G — Registry‑mode (SnapshotKit) + List


## Phase G.5 — Refactoring & Module Decomposition
Goal: Improve maintainability before Phase H by splitting oversized CLI sources and isolating shared utilities.

Tasks
- G5.1: Break `Sources/ios-snap/CLI.swift` into feature-specific files (render, list, devices, batch) wired through the main entry point.
- G5.2: Extract simulator and runner orchestration helpers into dedicated types or namespaces (e.g., `RenderingPipeline`, `DeviceCommands`).
- G5.3: Update imports and module structure; add targeted tests or smoke checks covering the refactored components.

Done when
- Project builds and existing commands behave the same with the new file layout.

Verify
- Run: `swift build`
- Run: `swift run ios-snap --help`
- Sanity check: `swift run ios-snap devices`

Goal: Render scenes registered at runtime and list them.

Tasks
- G1: Implement `SnapshotRegistry` with static map `[String: () -> AnyView]` and simple register API.
- G2: Runner path: if `SNAP_SCENE_ID` set, build AnyView from registry or exit with code 7 when missing.
- G3: `ios-snap list`: small helper target or runtime probe to print registry keys.
- G4: Provide Examples/Registry demo app with two scenes.

Done when
- `ios-snap list` prints scene ids in demo app; `render --scene` writes PNG.

Verify
- Build demo app, run `ios-snap list` → shows `locks/default` etc.; render to file

---

## Phase H — Batch Mode (YAML)
Goal: Run multiple scenes/variants from a config with validation.

Tasks
- H1: Add `Yams` dependency and parse YAML to structs (schema in docs/BATCH_CONFIG.md).
- H2: Validate each scene and variant; merge `global` defaults.
- H3: Iterate, invoke internal render flow; support `--continue-on-error` flag.
- H4: Summarize results; non‑zero exit on first failure by default.

Done when
- Batch produces all files for provided Examples/Snapshots.yml.

Verify
- Run: `ios-snap batch --config Examples/Snapshots.yml` → outputs exist; error behavior matches flags

---

## Phase I — Self‑Tests, Docs, CI
Goal: Ensure repeatability and developer experience.

Tasks
- I1: Add `Scripts/selftest.sh` implementing SPEC tests 1–6.
- I2: Polish logs and errors; ensure temp cleanup on success and helpful paths on failure.
- I3: Finalize docs (README, CLI_REFERENCE, TROUBLESHOOTING); add CI workflow suggestion.

Done when
- Self‑tests pass locally; docs reflect actual behavior.

Verify
- Run: `bash Scripts/selftest.sh` → exit 0

---

## Phase J — SwiftPM Command Plugin
Goal: Provide a `swift package ios-snap …` entrypoint that shells out to the existing CLI.

Tasks
- J1: Add a command plugin target that depends on the `ios-snap` executable.
- J2: Implement the plugin to forward arguments/output to the CLI binary.
- J3: Document plugin usage in README and CLI reference.

Done when
- `swift package ios-snap --help` prints the CLI usage.

Verify
- Run: `swift package ios-snap --help`

---

## Phase J.5 — Refactoring & Best Practices
Goal: Improve maintainability, readability, and extensibility before Phase K by enforcing single-responsibility structure, reducing function size, and introducing a Command-pattern pipeline for sequential operations.

Scope
- CLI commands and support utilities under `Sources/ios-snap`.
- Runner pipeline orchestration and validators.
- Minimal touch to Runner template (structuring helpers via private extensions) without behavior changes.

Tasks
- J5.1: File decomposition (SRP)
  - Further split `Support/RenderWorkflow.swift` into focused files: `RenderParams.swift` (parsing/validation), `RenderEnvironment.swift` (env/args assembly), `RenderOrchestrator.swift` (only composition), `StatusBarOverride.swift` (parsing/args).
  - Consider splitting `SimulatorManager` into protocol + concrete implementation to isolate simctl I/O from device selection logic.
- J5.2: Function decomposition (SRP)
  - Break long methods into private helpers; group via `private extension` blocks for structure.
  - Keep logs concise with phase tags per CODING_STYLE.
- J5.3: Command-pattern pipeline
  - Define `StepCommand` protocol with `name`, `execute(context:)`.
  - Implement steps: `PrepareWorkspace`, `ResolveDevice`, `BootDevice`, `ApplyStatusBar`, `BuildRunner`, `InstallRunner`, `LaunchRunner`, `PullOutput`, `ClearStatusBar`, `CleanupWorkspace`.
  - Replace inline sequences in `RenderWorkflow.performRender()` with a composed pipeline; preserve exit codes and messages.
- J5.4: Error handling
  - Centralize error-to-exit-code mapping for the commands; remove duplication.
- J5.5: Readability polish
  - Rewrap long lines/arg arrays; keep function bodies short.
- J5.6: Non-functional verification
  - `swift build`, `swift run ios-snap --help`, `swift run ios-snap devices`.

Done when
- Project builds; behavior unchanged for existing commands.
- Render flow uses Command-pattern orchestration internally without regressions.
- Files/functions adhere to SRP; internal helpers are private.

Verify
- Run: `swift build`
- Run: `swift run ios-snap --help`
- Run: `swift run ios-snap devices`

---

## Milestones & Artifacts
- M1: CLI skeleton runnable (Phases A–B)
- M2: `devices` working (C)
- M3: Runner builds (E)
- M4: First PNG from snippet (F)
- M5: Registry scenes + list (G)
- M6: Batch YAML (H)
- M7: Self‑tests + docs (I)
- M7.5: Refactoring & best practices (J.5)
- M8: External dependencies (K)

---

## Rollback & Cleanup
- Always clear status bar overrides on error paths.
- Remove temp dirs on success; retain on failure and log their path.

---

## Open Questions to Confirm
- Acceptable minimum iOS deployment target for Runner (17.0 ok?).
- Bundle identifier `com.example.Runner` vs. customizable.
- Do we need locale launch args in MVP (`-AppleLanguages`, `-AppleLocale`) or later?

---

## Phase K — External Dependencies (Workspace/Project/Package)
Goal: Allow the template Runner to see and link external frameworks/products so snippet/registry can render views from multi-module apps without manually editing the template.

Approach (incremental):
- K1: Flags + Validation
  - Add/confirm CLI flags: `--workspace <.xcworkspace>`, `--project <.xcodeproj>`, `--dep-scheme <Name>` (repeatable), `--package <path>`, `--product <Name>` (repeatable).
  - Validate path existence; require at least one dependency source when any of these flags are present.

- K2: Build Host Artifacts (Xcode projects/workspaces)
  - For each `--dep-scheme`, run `xcodebuild -workspace|project ... -scheme <Name> -sdk iphonesimulator -configuration Release` to produce simulator frameworks/libs into a staging dir under the runner workspace.
  - Collect product names (e.g., `CheckoutUI`) and provide build settings for Runner: `FRAMEWORK_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, `SWIFT_INCLUDE_PATHS`, and `OTHER_LDFLAGS` with `-framework <Product>` (or `-l<lib>` for static libs).

- K3: Build Host Artifacts (SwiftPM packages)
  - Run `xcodebuild` from the package root, infer the package scheme, and build the requested `--product` target for `iphonesimulator` with `-destination 'generic/platform=iOS Simulator'`.
  - Stage artifacts next to K2 outputs and reuse the same search-path/linker injection.
  - Document limitation: packages must build for `iphonesimulator`, recommended `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` for Swift interface compatibility.

- K4: Runner Build Overrides
  - Augment `RunnerPipeline.buildRunner()` to pass build-setting overrides via `xcodebuild` arguments rather than mutating the project file.
  - Keep snippet/registry behavior identical when no external flags are provided.

- K5: Batch Support
  - Extend batch schema to accept `workspace`, `project`, `dep_schemes`, `packages`, `products` at `global`/scene/variant levels; resolve paths relative to config.

- K6: Examples + Tests
  - Add an example framework + sample package in `Examples/ExternalDeps` and a mini batch config demonstrating both flows.
  - Self-test step: render a view from the external framework using snippet-mode with `--workspace/--dep-scheme`.

Done when
- Snippet-mode can render a public view from a framework built via `--workspace/--dep-scheme`.
- Batch can reference the same external config and produce outputs.
- Optional: Package flow renders using `--package/--product` on hosts with Xcode 15+.

Verify
- Run: `ios-snap render --snippet Snapshots/View.swift --workspace MyApp.xcworkspace --dep-scheme CheckoutUI --device 'iPhone 15' --out screens/ui.png`.
- Run: `ios-snap batch --config Examples/ExternalDeps.yml`.

Risks & Mitigations
- Complex Xcode project mutations: avoid editing `.pbxproj`; inject `FRAMEWORK_SEARCH_PATHS`/`OTHER_LDFLAGS` at build time.
- Swift module compatibility: document `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` recommendation.
- Mixed archs: target `-destination 'generic/platform=iOS Simulator'` and prefer per-arch staging if needed later.
