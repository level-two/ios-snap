# Phase J.5 — Refactoring & Best Practices

Objective: Prepare the codebase for external dependencies (Phase K) and future features by applying SRP, shrinking functions, and adopting a lightweight Command pipeline for sequential operations.

## Principles
- Single Responsibility: one type/file has one reason to change.
- Small Functions: compose behavior from concise, focused helpers.
- Encapsulation: hide implementation details via `private`/`fileprivate` and `internal` default.
- Readability: short lines, clear names, consistent logging (`[sim]`, `[build]`, `[run]`, `[pull]`).
- No behavior changes: refactor is structural only.

## Targets
- ios-snap (CLI + Support): main focus of decomposition.
- Runner: structure helpers as private extensions if needed; avoid behavior changes.
- SnapshotKit: only light polishing (e.g., file structure) if necessary.

## Step-by-Step Plan
1) Inventory hot spots
   - Identify large files/functions (RenderWorkflow, SimulatorManager, RunnerPipeline) and map responsibilities.

2) File decomposition
   - Split RenderWorkflow into:
     - `RenderParams.swift` — parse flags, validate basics
     - `RenderEnvironment.swift` — assemble env/args, orientation/size logic
     - `RenderOrchestrator.swift` — orchestrate steps only
     - `StatusBarOverride.swift` — parse/canonicalize/cli args
   - Consider splitting SimulatorManager: JSON decoding + device selection separate from simctl I/O.

3) Function decomposition
   - Extract helpers per responsibility; gather them in `private extension Type` blocks (e.g., parsing, validation, env assembly).

4) Command-pattern pipeline
   - Define `protocol StepCommand { var name: String { get } func execute(inout context) throws }` (exact signature may vary).
   - Implement steps: PrepareWorkspace → ResolveDevice → BootDevice → ApplyStatusBar → BuildRunner → InstallRunner → LaunchRunner → PullOutput → ClearStatusBar → CleanupWorkspace.
   - Provide a `Pipeline` runner that logs start/finish per step and maps errors to exit codes consistently.

5) Error handling & logging
   - Centralize mapping to exit codes; remove ad-hoc conversions.
   - Keep logs single-line with phase tags.

6) Readability & style polish
   - Rewrap long lines and commands; keep arrays readable (one argument per line if long).

7) Smoke verification
   - `swift build`, `swift run ios-snap --help`, `swift run ios-snap devices`.

## Acceptance
- Build succeeds; no behavior changes to existing commands.
- Render orchestration uses the pipeline with equivalent logs and exit codes.
- Files/functions reflect SRP; helpers are private.

## Risks
- Hidden regressions in edge-case error handling → mitigate with small, focused step conversion and incremental testing.
- Over-abstraction → prefer minimal protocol surface for commands and keep types local to `Support`.

## Notes
- Do not add formatters/config unless already present; follow `docs/CODING_STYLE.md`.
- Avoid `.pbxproj` mutations; Phase K will inject build settings at xcodebuild time.
