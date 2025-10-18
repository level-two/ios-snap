# Phase G.5 — CLI Refactor Strategy

Objective: reduce `Sources/ios-snap/CLI.swift` size and clarify responsibilities before Phase H.

## Target Modules
- `Commands/DevicesCommand.swift`
- `Commands/RenderCommand.swift`
- `Commands/BatchCommand.swift`
- `Commands/ListCommand.swift`
- `Support/RenderPipeline.swift` (xcodebuild + simctl orchestration)
- `Support/Logging.swift` (IosSnapIO)
- `Support/Validators.swift` (shared parsing helpers)

## Migration Steps
1. Introduce a `Commands` subfolder under `Sources/ios-snap` and move one command at a time.
2. Extract shared helpers (`describeSimulatorError`, path expansion, locale parsing) into dedicated support files.
3. Update `Package.swift` target to include new sources (SwiftPM picks them automatically by folder).
4. Ensure `main.swift` registers the new command structs via `CommandConfiguration`.
5. After each move run `swift build` and a quick smoke test: `swift run ios-snap devices`.

## Risks & Mitigations
- **Accidental behavior changes**: add inline TODO comments referencing original logic; run host smoke tests after major moves.
- **Circular dependencies**: keep helpers free of command-specific imports and prefer parameter injection.
- **Regressions in render flow**: once support structs extracted, re-run `render` and `list` commands before proceeding to Phase H.

## Open Questions
- Should simulator utilities become a separate module (e.g., `SimulatorKit`)? Defer until after initial extraction.
- Would unit tests add value here? Consider lightweight tests for argument parsing once structure stabilizes.
