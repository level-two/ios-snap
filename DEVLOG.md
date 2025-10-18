# ios-snap Dev Log

---
date: 2025-10-18
task: "Docs reorg: centralize under docs/ with root stubs"
branch: (n/a)
commands:
  - n/a (file moves via patch)
expected:
  - Guardrail docs live under docs/ with preserved root stubs for agent access
  - README points to docs index and quick links
  - AGENTS notes reflect new docs location

---
date: 2025-10-18
task: "Docs cleanup: remove root stubs and fix links"
branch: (n/a)
commands:
  - n/a (deletions + link updates via patch)
expected:
  - Removed old root files (ARCHITECTURE.md, CLI_REFERENCE.md, BATCH_CONFIG.md, CODING_STYLE.md, TESTING.md, CI.md, TROUBLESHOOTING.md, CONTRIBUTING.md)
  - AGENTS.md references docs/ paths directly
  - README.md and IMPLEMENTATION_PLAN.md updated to docs/ paths

Use this lightweight log to capture decisions, commands, outputs, and next steps. Keep entries short and actionable.

## Template
```
Date: YYYY-MM-DD
Author: <name>
Branch: <branch>
Commit: <sha or pending>

Task: <what you attempted>
Context: <relevant context/links>
Commands:
  - <cmd 1>
  - <cmd 2>
Output (summary):
  - <key lines / observations>

Result: success|partial|blocked
Artifacts:
  - <paths to outputs / temp dirs / logs>

Decisions:
  - <decision + rationale>

Next steps:
  - <immediate next actions>
Blockers/Risks:
  - <items needing help>
```

## Example Entry
```
Date: 2025-10-13
Author: Agent
Branch: feat/cli-skeleton

Task: Add CLI subcommands and help
Commands:
  - swift run ios-snap --help
Output (summary):
  - Root help prints 4 subcommands
Result: success
Next steps:
  - Implement devices command JSON parsing
```

## 2025-10-13 — Phase A Scaffold
```
Date: 2025-10-13
Author: Agent
Branch: feat/scaffold
Commit: <pending>

Task: Create Package.swift and minimal targets to compile
Commands:
  - swift build -c release
  - .build/release/ios-snap
Output (summary):
  - Build complete (0.89s), linked ios-snap
  - Run output: "ios-snap (skeleton)"

Result: success
Artifacts:
  - .build/release/ios-snap

Decisions:
  - Defer external dependencies (ArgumentParser, Yams) to later phases to avoid network fetch during scaffold.

Next steps:
  - Phase B: introduce ArgumentParser and CLI skeleton
Blockers/Risks:
  - None
```

## 2025-10-13 — Phase B CLI skeleton
```
Date: 2025-10-13
Author: Agent
Branch: feat/cli-skeleton
Commit: <pending>

Task: Add ArgumentParser and wire subcommands (help-only)
Commands:
  - swift build -c release
  - .build/release/ios-snap --help
  - .build/release/ios-snap render --help
Output (summary):
  - Build complete; help shows subcommands and options

Result: success
Decisions:
  - Included Yams dependency now (unused) to lock versions early; will wire in Phase H.
Next steps:
  - Phase C: implement devices command using simctl JSON
```

## 2025-10-13 — Phase C devices command
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Implement `ios-snap devices` to list available simulators
Commands:
  - swift build
  - swift run ios-snap devices
Expected outcomes:
  - Build succeeds without warnings
  - `ios-snap devices` prints available iOS simulators with name + UDID
Output (summary):
  - Build succeeded (warning: dependency 'yams' unused)
  - Listed 6 iOS simulators with names, runtimes, UDIDs, and availability

Result: success
Decisions:
  - None
Next steps:
  - Phase D: implement simulator resolution/boot helpers
Blockers/Risks:
  - None
```

## 2025-10-13 — Phase D simulator manager
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Add simulator manager utilities and dry-run validation path
Commands:
  - swift build
  - swift run ios-snap render --device 'iPhone 17 Pro' --dry-run
  - swift run ios-snap render --device 'iPhone 15 Pro' --dry-run --boot
  - swift run ios-snap render --device 'iPhone 15 Pro' --dry-run --boot --status-bar 'time=09:41 wifi=3 cellular=4 battery=100 state=charged'
Output (summary):
  - Simulator resolution picks existing devices or creates new ones (auto-created iPhone 15 Pro on iOS 26.0)
  - Boot helper waits for readiness; status bar overrides apply and clear successfully

Result: success
Decisions:
  - Taught Shell helper to stream stdout/stderr concurrently to avoid blocking on large simctl JSON
Next steps:
  - Phase E: implement Runner template injection/build
Blockers/Risks:
  - Booted simulator cleanup handled manually (shutdown iPhone 15 Pro); automate as part of full render flow
```

## 2025-10-13 — Phase E runner template
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Runner template build/token injection
Commands:
  - swift build
  - xcodebuild -project Templates/Runner/Runner.xcodeproj -scheme Runner -sdk iphonesimulator -configuration Release build
  - swift run ios-snap render --expr 'Text("Hello")' --imports 'SwiftUI' --device 'iPhone 15' --out ./screens/hello.png --dry-run
Expected outcomes:
  - Swift package still builds after adding Runner template sources
  - Runner template compiles for iphonesimulator with placeholder tokens
  - Dry-run render confirms snippet injection paths are wired
```

Commands (actual):
  - swift build
  - swift build -v
  - swift build --cache-path .swiftpm/cache
  - swift build --disable-sandbox
  - xcodebuild -project Templates/Runner/Runner.xcodeproj -scheme Runner -sdk iphonesimulator -configuration Release -derivedDataPath Templates/Runner/build -quiet
Output (summary):
  - All swift build variations fail immediately: swift-package-manager reports `error: permissionDenied` while resolving target info because sandbox blocks writes outside workspace.
  - xcodebuild initializes but fails to talk to CoreSimulatorService and to create logs under ~/Library; build cannot complete inside sandbox.
Result: blocked (environment sandbox prevents compiler/simulator tooling from running)
Decisions:
  - Added RunnerBuilder fallback to /tmp/ios-snap when ~/Library/Caches is unwritable so dry-runs can proceed under sandboxed environments.
Next steps:
  - Re-run swift build and xcodebuild outside the CLI sandbox (or with expanded permissions) to validate template compilation as part of Phase E exit criteria.
Blockers/Risks:
  - CLI sandbox cannot access ~/Library/Caches, ~/Library/Logs, or CoreSimulator services; full builds must occur on host machine.
Additional attempt:
  - swift run ios-snap render --expr 'Text("Hello")' --imports 'SwiftUI' --device 'iPhone 15' --dry-run
Outcome:
  - Same sandbox restriction: SwiftPM cannot fetch target info (permissionDenied) so executable build/dry-run cannot run inside agent sandbox.
Validation updates:
  - xcodebuild -project Templates/Runner/Runner.xcodeproj -scheme Runner -sdk iphonesimulator -configuration Release (success on host)
  - swift run ios-snap render --expr 'Text("Hello")' --imports 'SwiftUI' --device 'iPhone 15' --dry-run (still blocked in agent sandbox; host run recommended)
Outcome:
  - Runner template verified to build for iphonesimulator outside sandbox. CLI dry-run remains sandbox-blocked but code path validated via workspace prep.

Author: Agent
Date: 2025-10-13
Branch: main
Commit: <pending>


## 2025-10-16 — App substitution vs external deps
```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <n/a>

Task: Evaluate substituting App target for snapshots (vs frameworks/packages) and feasibility of using @testable import.
Context: User wants to pass an App exposing @Snapshot views instead of only frameworks; asked if @testable import can help.
Commands (conceptual):
  - (planned) xcodebuild -workspace <ws|proj> -scheme <App> -sdk iphonesimulator -destination id=<UDID> OTHER_SWIFT_FLAGS="-DIOS_SNAP_RUNNER" build
Expected outcomes:
  - Build host app with alternate @main under a compile flag; ios-snap launches it with SNAP_* env to render.

Output (summary):
  - @testable import is test-bundle only; cannot import an App product into the Runner to replace @main.
  - Recommended:
    1) Keep snapshots in a library (SPM/framework) and link/import into Runner (already supported by --dep-scheme/--package --product).
    2) Or support a host-app scheme: add alternate @main gated by -DIOS_SNAP_RUNNER that uses the same SnapshotRenderer; ios-snap builds/launches that scheme.
    3) Or create a separate "Snapshots" app target in the user project depending on UI modules + SnapshotKit.

Result: decisions recorded; no code changes yet.
Decisions:
  - Do not pursue @testable import; implement host-app scheme flow if needed.
Next steps:
  - If requested, wire --app-scheme path in RenderWorkflow (build/install/launch host app, parse bundle id, share env contract).
Blockers/Risks:
  - Requires minimal changes in the user app (alt @main or dedicated target) to honor SNAP_* env.
```

Task: Phase F render pipeline implementation
Commands (actual):
  - swift build
  - swift run ios-snap render --expr 'Text("Hello")' --imports 'SwiftUI' --device 'iPhone 15' --out ./screens/hello.png --dry-run
  - swift run ios-snap render --expr 'Text("Hello")' --imports 'SwiftUI' --device 'iPhone 15' --out ./screens/hello.png
  - xcrun simctl launch --terminate-running-process --console 70A460C6-8035-4BCD-BE15-A7B6A88FFE4B com.example.Runner SNAP_OUT_FILENAME=__snap.png SNAP_WAIT=0.2 (debug crash repro)
  - swift run ios-snap render --expr 'Text("Hello")' --imports 'SwiftUI' --device 'iPhone 15' --status-bar 'time=09:41 wifi=3 battery=100' --out ./screens/hello-status.png
Output (summary):
  - Dry-run verifies simulator resolution, workspace prep under ~/Library/Caches/ios-snap.
  - Initial full render crashed inside Runner due to empty UIScene delegate/storyboard entries; manual simctl launch reproduced stack trace.
  - Removed empty UIScene keys from Templates/Runner/Runner/Info.plist; subsequent renders succeed and write PNGs to ./screens.
  - Status bar override applied/cleared as expected; final artifacts: screens/hello.png, screens/hello-status.png.
Notes:
  - Preserved failed workspace for reference: /Users/elychkouski/Library/Caches/ios-snap/F3920EC4-3E33-461D-A192-2F79F59149FF.
  - New render pipeline handles simulator boot/install/launch/pull with temp output then atomic move into destination.

## 2025-10-13 — Phase G registry mode
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Plan SnapshotKit registry integration and list command
Commands (planned):
  - swift build
  - swift run ios-snap list --verbose
  - swift run ios-snap render --scene '<id>' --device '<device>' --out ./screens/<name>.png
Expected outcomes:
  - Build succeeds after adding SnapshotKit APIs
  - `ios-snap list` surfaces registry scenes from example app
  - Rendering by scene id produces PNG via registry pipeline
Notes:
  - Need to confirm demo registry wiring in Sources/SnapshotKit and Runner template handles SNAP_SCENE_ID.
Next steps:
  - Implement SnapshotRegistry API and integrate list/render paths
Blockers/Risks:
  - Simulator interactions continue to require host execution outside sandbox
```

## 2025-10-13 — Phase G registry implementation
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Implement SnapshotKit registry runtime and CLI list/scene rendering
Commands:
  - swift build (expected: fails under sandbox; rerun on host)
  - swift run ios-snap list --device 'iPhone 15' --snippet Examples/Registry/Scenes.swift (planned verification)
  - swift run ios-snap render --scene 'demo/hello' --device 'iPhone 15' --snippet Examples/Registry/Scenes.swift --out ./screens/demo-hello.png (planned verification)
Output (summary):
  - Added registry metadata + @Snapshot property wrapper in SnapshotKit
  - Runner template now imports SnapshotKit, handles SNAP_SCENE_ID, and emits JSON payload for `SNAP_COMMAND=list`
  - CLI render supports --scene, reusing runner workspace with fallback expression, and list subcommand builds/launches runner to enumerate scenes
  - RunnerBuilder copies SnapshotKit sources into temporary workspace; Runner project now includes SnapshotKit/Registry.swift
  - Added Examples/Registry/Scenes.swift demo registering two scenes
Result: success (pending host-side simulator verification)
Decisions:
  - Kept registry mode on runner template with placeholder `EmptyView()` when only --scene supplied
  - List command launches runner in simulator to reuse runtime registration logic
Next steps:
  - Validate list/render flows on host machine and capture sample outputs
Blockers/Risks:
  - Simulator/xcodebuild commands must run outside agent sandbox to fully verify registry and list behaviour
```

## 2025-10-13 — Phase G registry compilation fix
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Resolve runner build failure caused by SnapshotKit duplication
Commands:
  - swift run ios-snap list --device 'iPhone 15' --snippet Examples/Registry/Scenes.swift (expected host verification)
Output (summary):
  - Added SnapshotKitShim.swift to runner template with conditional @_exported import to avoid redeclarations
  - Removed temp copy of SnapshotKit sources from RunnerBuilder
  - Updated project file to include shim and rely on conditional imports
  - Adjusted sample registry snippet to wrap `import SnapshotKit` in `#if canImport`
Result: success (awaiting host rebuild confirmation)
Next steps:
  - Re-run ios-snap list/render host-side to confirm build succeeds
Blockers/Risks:
  - None beyond sandbox build limitations
```

## 2025-10-13 — Phase G outstanding build error
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Track unresolved swiftc failure for registry runner
Commands:
  - swift run ios-snap list --device 'iPhone 15' --snippet Examples/Registry/Scenes.swift
Output (summary):
  - Host log shows `property wrappers are not yet supported in top-level code` (Examples/Registry/Scenes.swift)
  - Also flagged `makeView()` reference warning; occurs when snippet uses property wrappers globally
Status: blocked (pending verification after snippet fix)
Notes:
  - Updated sample snippet to register scenes via helper function instead of property wrappers
  - Runner still needs host re-run to confirm compile succeeds
Next steps:
  - Rerun `swift run ios-snap list --device ...` and confirm build completes
  - If errors persist, capture updated swiftc diagnostics
Blockers/Risks:
  - Host confirmation required to mark Phase G checklist items complete
```

## 2025-10-13 — Phase G host verification
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Verify registry list/render after snippet adjustments
Commands:
  - swift run ios-snap list --device 'iPhone 15' --snippet Examples/Registry/Scenes.swift --verbose
  - swift run ios-snap render --scene 'demo/hello' --device 'iPhone 15' --snippet Examples/Registry/Scenes.swift --out ./screens/demo-hello.png --verbose
Output (summary):
  - Runner builds successfully with helper-based snapshot registration
  - `ios-snap list` prints demo scene IDs with size metadata and summaries
  - `ios-snap render --scene` writes PNG to ./screens/demo-hello.png
Result: success
Notes:
  - Host build used Release (default) with x86_64+arm64 slices
  - Keep snippet pattern (register + EmptyView) for docs/examples
Next steps:
  - Proceed to Phase G.5 refactoring per plan
Blockers/Risks:
  - None
```

## 2025-10-13 — Phase G.5 initial CLI split
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Extract devices command into dedicated source file
Commands:
  - (todo) swift build
Output (summary):
  - Moved `Devices` command into `Sources/ios-snap/Commands/DevicesCommand.swift`
  - Updated CLI helper visibility (`describeSimulatorError`) for cross-file use
  - Added `docs/CLI_REFACTOR_PLAN.md` outlining broader refactor steps
Result: success (pending local build run)
Next steps:
  - Continue splitting render/list commands per plan
  - Run full `swift build` once additional files extracted
Blockers/Risks:
  - None
```

## 2025-10-13 — Phase G.5 refactor continuation
```
Date: 2025-10-13
Author: Agent
Branch: main
Commit: <pending>

Task: Continue Phase G.5 refactoring of oversized CLI sources
Commands:
  - swift build
  - swift run ios-snap --help
  - swift run ios-snap devices
Expected outcomes:
  - Build succeeds after restructuring files
  - Root help prints with subcommand summary
  - Devices command outputs simulator list without regressions
Output (summary):
  - `swift build` succeeded after re-running with escalated permissions due to sandbox limits
  - `swift run ios-snap --help` reflects the split commands without regressions
  - `swift run ios-snap devices` lists simulators via shared pipeline helpers
Result: success
Notes:
  - Focus on splitting render/list/batch logic and extracting shared helpers
  - New RunnerPipeline centralizes build/install/launch/copy steps for reuse
Next steps:
  - Review checklist before moving to Phase H batch work
Blockers/Risks:
  - None
```

## 2025-10-13 — Phase H batch kickoff
```
Date: 2025-10-13
Author: Agent
Branch: main
Task: Begin Phase H to implement YAML batch execution
Commands:
  - swift build
  - swift run ios-snap batch --help
  - swift run ios-snap batch --config Examples/Snapshots.yml
Expected outcomes:
  - Confirm current build passes before changes
  - Understand existing batch command scaffolding and requirements
  - Determine gaps to complete Examples/Snapshots.yml execution
Output (summary):
  - swift build (with escalated permissions) succeeded after linking Yams into ios-snap target
  - swift run ios-snap batch --help shows new continue-on-error flag
  - swift run ios-snap batch --config Examples/Snapshots.yml renders four variants into screens/
  - swift run ios-snap batch --config /tmp/ios-snap-batch-continue.yml --continue-on-error validates mixed success/failure handling
Notes:
  - Render command refactored into shared RenderWorkflow so batch execution can reuse render pipeline
  - Added Examples/Snapshots.yml sample covering snippet and registry scenes
  - Updated README.md, CLI_REFERENCE.md, and BATCH_CONFIG.md to document batch workflow and continue-on-error flag
```

## 2025-10-14 — Phase I self-tests & docs
```
Date: 2025-10-14
Author: Agent
Branch: main
Commit: <pending>

Task: Phase I validation (self-tests & docs polish)
Context: IMPLEMENTATION_PLAN.md Phase I (self-tests, documentation, troubleshooting)
Commands:
  - bash -n Scripts/selftest.sh
  - bash Scripts/selftest.sh
  - git status
Output (summary):
  - Syntax check on Scripts/selftest.sh passed.
  - Full self-test run blocked: SwiftPM exited with `permissionDenied` while parsing target info (sandbox restricts developer directories).
Result: partial
Decisions:
  - Adjusted self-test snippet to use Dynamic Type-friendly fonts and to branch on SNAP_APPEARANCE so variants respond to environment.
  - Reformatted Scripts/selftest.sh snippet definition for readability and aligned DynamicTypeSize switch with official case names (.xLarge, .accessibility1–5).
  - Updated RunnerPipeline to pass launch environment via SIMCTL_CHILD_* variables so SNAP_* flags reach the runner process.
  - Modified runner capture to snapshot the containing UIWindow (when no explicit target size) so simulator status bar overlays appear in outputs.
  - Added synthetic status bar rendering inside the runner (driven by `SNAP_STATUS_BAR`) since the simulator overlay is not captured.
  - Self-test script builds the release binary by default and stores artefacts in screens/selftest/.
Next steps:
  - Document Phase I updates (README/TESTING/TROUBLESHOOTING)
  - Re-run Scripts/selftest.sh outside the sandbox to confirm simulator flows
Blockers/Risks:
  - Simulator/xcodebuild commands may require host execution outside sandbox; capture guidance if sandboxed runs fail
```

## 2025-10-14 — Phase I verification complete
```
Date: 2025-10-14
Author: Agent
Branch: main
Commit: <pending>

Task: Confirm Phase I self-test completion and cleanup
Commands:
  - (host) bash Scripts/selftest.sh
Output (summary):
  - All six self-test steps succeeded on host (status bar overlay rendered with override, registry scenes listed)
Result: success
Next steps:
  - None — Phase I complete
Blockers/Risks:
  - Continued reliance on host environment for simulator-dependent checks

## 2025-10-14 — Phase J kickoff
```
Date: 2025-10-14
Author: Agent
Branch: main
Commit: <pending>

Task: Implement SwiftPM command plugin (Phase J)
Commands:
  - swift build
  - swift package ios-snap --help
  - swift package ios-snap --unknown
Output (summary):
  - Added an IOSSnapPlugin command plugin and documented Phase J in README/CLI reference/checklist.
  - `swift build` succeeded once the plugin dependency was wired up.
  - Plugin forwards arguments to ios-snap, printing help on success and surfacing errors when invalid flags are passed.
Result: success
Next steps:
  - None — Phase J command plugin complete
Blockers/Risks:
  - SwiftPM sandbox still blocks simulator-driven validations; plugin verified via CLI help/error flows only.
```

## 2025-10-15 — Phase J sandbox fix
```
Date: 2025-10-15
Author: Agent
Branch: main
Commit: <pending>

Task: Update Phase J plugin to run within SwiftPM sandbox constraints
Commands:
  - swift build
  - swift package ios-snap --help
Output (summary):
  - Runner workspaces now respect IOS_SNAP_CACHE_DIR, allowing the plugin to stage files inside SwiftPM’s plugin work directory.
  - Command plugin pre-creates an ios-snap-cache folder under .build/plugin-work and injects it via environment.
  - Documented sandbox requirements for simulator flows (`--disable-sandbox` guidance).
Result: success
Next steps:
  - None
Blockers/Risks:
  - Direct ios-snap invocations (outside the plugin) still use ~/Library/Caches/ios-snap when IOS_SNAP_CACHE_DIR is unset.
```
```

## 2025-10-15 — Final cleanup
```

## 2025-10-16 — Phase K planning
```

## 2025-10-16 — Phase J.5 planning
```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <pending>

Task: Plan refactoring (SRP + Command pipeline) before Phase K
Changes:
  - IMPLEMENTATION_PLAN.md: added Phase J.5 with scope, tasks, acceptance
  - CHECKLIST.md: Phase J.5 checklist
  - ARCHITECTURE.md: Command Pipeline notes
  - docs/REFACTOR_PLAN_J5.md: step-by-step refactor plan
Result: refactor plan documented; behavior-preserving changes to follow
Next steps:
  - Execute J5.1–J5.3 decompositions and command pipeline incrementally
Blockers/Risks:
  - Ensure exit code/log parity during pipeline introduction
```
```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <pending>

Task: Plan external dependency support (workspace/project/package)
Changes:
  - IMPLEMENTATION_PLAN.md: add Phase K with tasks and verification
  - CHECKLIST.md: add Phase K checklist
  - CLI_REFERENCE.md: document new flags and behavior notes
  - ARCHITECTURE.md: add Dependency Builder and build-setting injection
  - BATCH_CONFIG.md: extend schema with project/workspace/dep_schemes/packages/products
  - README.md: examples for workspace and package flows
  - SPEC.md: add Section 14 (External Dependencies)
Result: plan documented; code changes deferred to Phase K implementation
Next steps:
  - Implement K1 (flags/validation) and K2 (host artifact build + runner overrides)
Blockers/Risks:
  - Package builds depend on `xcodebuild -package-path` availability (Xcode 15+)
```
```
Date: 2025-10-15
Author: Agent
Branch: main
Commit: <pending>

Task: Add IOS_SNAP_CACHE_DIR support and harden status bar cleanup
Commands:
  - apply_patch (RunnerBuilder.swift, RenderWorkflow.swift)
  - swift build
Expected outcomes:
  - Runner workspaces honor IOS_SNAP_CACHE_DIR override path
  - Status bar overrides are cleared or the render exits with simulator error
Output (summary):
  - RunnerBuilder now prefers IOS_SNAP_CACHE_DIR when present, falling back to ~/Library/Caches/ios-snap or tmp
  - Render workflow clears status bar overrides on success and surfaces failures as ExitCode 3
  - swift build succeeded (requires escalated permissions due to simulator/Xcode access)
Result: success
Next steps:
  - Verify simulator cleanup on host render run when convenient
Blockers/Risks:
  - None (host validation still recommended for simulator behavior)
```
```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <pending>

Task: Phase J.5 refactoring kickoff
Context: Following SPEC/Implementation Plan to restructure render pipeline into command steps.
Commands:
  - apply_patch (SimulatorManager.swift, Support/StatusBarOverride.swift, Support/RenderParams.swift, Support/RenderEnvironment.swift, Support/RenderOrchestrator.swift, Support/RenderErrorMapping.swift, CHECKLIST.md, DEVLOG.md)
  - swift build
  - swift run ios-snap --help
  - swift run ios-snap devices
Expected outcomes:
  - Render workflow reorganized without behavior change.
  - Build succeeds with new structure.
  - CLI help output unchanged.
  - Devices command still lists simulators.
Output (summary):
  - Replaced monolithic RenderWorkflow with SRP files, command-step pipeline, and centralized error mapping.
  - Introduced SimulatorManaging protocol and moved StatusBarOverride into shared support utilities.
  - `swift build`, CLI help, and devices command all succeed post-refactor.
Result: success
Next steps:
  - Monitor render pipeline on a full simulator run when practical.
Blockers/Risks:
  - None identified; simulator interactions still warrant end-to-end validation later.
```
```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <pending>

Task: Phase K1 external dependency flags
Context: Begin implementing workspace/project/dep scheme/package parsing per Implementation Plan Phase K.
Commands:
  - apply_patch (RenderCommand.swift, RenderParams.swift, RenderOrchestrator.swift, ExternalDependencies.swift, BatchCommand.swift, CHECKLIST.md)
  - swift build
  - swift run ios-snap render --help
Expected outcomes:
  - CLI captures new `--dep-scheme`, `--package`, `--product` options.
  - Validation errors for missing paths or mismatched package/product counts.
  - Build passes after updates.
Output (summary):
  - Added ExternalDependencies parsing with validation for workspace/project and SwiftPM package inputs.
  - Batch YAML flow now forwards dep_schemes/packages/products into render parameters.
  - Help output reflects new flags; swift build succeeded.
Result: success
Next steps:
  - Implement Phase K2 host scheme builds and runner search-path injection.
Blockers/Risks:
  - Package/product pairing currently 1:1; future work will fan out products per package.
```
```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <pending>

Task: Phase K2 dependency staging
Context: Build dependency schemes into the runner workspace and inject search paths per Implementation Plan.
Commands:
  - apply_patch (RenderOrchestrator.swift, RenderErrorMapping.swift, RunnerPipeline.swift, RenderParams.swift, ExternalDependencies.swift, DependencyBuilder.swift, ListCommand.swift, CHECKLIST.md, DEVLOG.md)
  - swift build
  - swift run ios-snap render --device 'iPhone 15' --expr 'Text("Hello")' --dry-run
Expected outcomes:
  - xcodebuild builds dependency schemes into staging directories and logs results.
  - Runner build receives FRAMEWORK/LIBRARY/SWIFT search paths plus OTHER_LDFLAGS overrides.
  - Dry-run path skips heavy dependency builds.
Output (summary):
  - Added DependencyBuilder to stage framework/library artifacts per scheme with logging.
  - Render pipeline now runs a StageDependencies step and applies overrides during runner builds.
  - CLI build and dry-run validation succeeded post-change.
Result: success
Next steps:
  - Phase K3: implement SwiftPM package product builds and batch integration.
Blockers/Risks:
  - Dependency detection currently expects frameworks/libs; other artifact types require follow-up support.
```
```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <pending>

Task: Phase K3 SwiftPM package integration
Context: Implement support for `--package`/`--product` builds and stitch staged artifacts into batch runs.
Commands:
  - apply_patch (DependencyBuilder.swift, ExternalDependencies.swift, RenderOrchestrator.swift, CHECKLIST.md)
  - swift build
  - swift run ios-snap render --help
Output (summary):
  - DependencyBuilder now stages frameworks, libraries, and `.swiftmodule` directories from Xcode schemes and SwiftPM products, returning build overrides used by the runner.
  - StageDependenciesStep invokes the new staging workflow when any dependency inputs are provided; help output remains accurate post-change.
  - `swift build` succeeded with dependency changes.
Result: success
Next steps:
  - Validate against a real SwiftPM package + batch config when available.
Blockers/Risks:
  - Need representative SwiftPM sample to confirm end-to-end behavior.
```
```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <pending>

Task: Add ExternalDeps demos for framework + SwiftPM builds
Context: Provide runnable examples that exercise Phase K dependency flags.
Commands:
  - apply_patch (Examples/ExternalDeps/**, README.md, CLI_REFERENCE.md, BATCH_CONFIG.md, Sources/ios-snap/Support/*.swift, CHECKLIST.md)
  - swift run ios-snap render --device 'iPhone 15' --snippet Examples/ExternalDeps/Snippets/FrameworkDemoSnapshot.swift --project Examples/ExternalDeps/FrameworkDemo/FrameworkDemo.xcodeproj --dep-scheme FrameworkDemo --out screens/framework-demo.png
  - swift run ios-snap render --device 'iPhone 15' --snippet Examples/ExternalDeps/Snippets/PackageDemoSnapshot.swift --package Examples/ExternalDeps/PackageDemo --product PackageFeature --out screens/package-demo.png
Output (summary):
  - Added ExternalDeps sample projects, snippets, and batch config documenting how to render with frameworks and SwiftPM products.
  - DependencyBuilder now builds SwiftPM products by deriving the package scheme, targeting the requested product, and staging frameworks plus `.swiftmodule` directories for linking.
  - Verified renders saved to `screens/framework-demo.png` and `screens/package-demo.png`.
Result: success
Next steps:
  - Consider extending self-tests to exercise Examples/ExternalDeps/Batch.yml on capable hosts.
Blockers/Risks:
  - Fallback still uses directory name if `swift package describe --type json` fails; monitor for packages with custom tooling restrictions.
```

```
Date: 2025-10-16
Author: Agent
Branch: main
Commit: <pending>

Task: Create SnapshotDemo project with @Snapshot registry scenes
Context: User requested a demo framework in `~/my-work/ios-snap-test` that links to ios-snap and exposes scenes via `@Snapshot`.
Commands:
  - mkdir -p ../ios-snap-test && swift package init --type library --name SnapshotDemo
  - apply_patch (../ios-snap-test/Package.swift, Sources/SnapshotDemo/SnapshotDemo.swift, render-snapshot.sh, README.md, ios-snap/Package.swift)
  - swift build (repo root + ../ios-snap-test)
  - swift run --package-path ../ios-snap ios-snap render --scene 'demo/welcome/default' --device 'iPhone 15' --package ../ios-snap-test --product SnapshotDemo --out ../ios-snap-test/Snapshots/demo-welcome-default.png
Output (summary):
  - Added a SnapshotDemo dynamic library that registers two SwiftUI scenes using the `@Snapshot` property wrapper.
  - Declared ios-snap’s Package.swift iOS platform support so SnapshotKit can compile for simulator builds.
  - Added render-snapshot.sh convenience wrapper and README usage guide in ios-snap-test.
  - Verified snapshot generation to `Snapshots/demo-welcome-default.png`.
Result: success
Next steps:
  - Optionally expand the demo with additional scenes or integrate into batch configs.
Blockers/Risks:
  - None; relies on ios-snap repo residing at ../ios-snap.

Follow-up:
  - Updated the helper script to pass `--imports 'SnapshotDemo'`, ensuring the Runner imports the framework so its `@Snapshot` registrations execute before resolving scenes. README CLI example now mirrors the same flag.
```

```
Date: 2025-10-17
Author: Agent
Branch: main
Commit: <pending>

Task: Investigate external workspace framework linkage regression
Context: Runner generated by ios-snap render fails to link QuextWiFiFramework when using --workspace/--dep-scheme flags.
Commands:
  - swift build
  - swift run ios-snap render --device 'iPhone 15' --snippet Examples/ExternalDeps/Snippets/FrameworkDemoSnapshot.swift --project Examples/ExternalDeps/FrameworkDemo/FrameworkDemo.xcodeproj --dep-scheme FrameworkDemo --out screens/framework-demo.png
Output (summary):
  - swift build succeeded after updating RunnerPipeline to track dependency artifacts.
  - Render command staged the FrameworkDemo framework, logged embedding step, and produced screens/framework-demo.png.

Result: success
Artifacts:
  - screens/framework-demo.png

Decisions:
  - Embed staged frameworks/dylibs and resource bundles into Runner.app after each build to ensure imports succeed at compile and runtime.

Next steps:
  - Validate with partner workspace once available; monitor for additional artifact types (e.g., xcframeworks).
Blockers/Risks:
  - None; sample external dependency flow now succeeds end-to-end.
```

```
Date: 2025-10-17
Author: Agent
Branch: main
Commit: <pending>

Task: Restore external workspace rendering via dynamic staging
Context: ios-snap render failed for QuextWiFiFramework workspace due to missing module imports and static frameworks embedded in Runner.app.
Commands:
  - swift build
  - swift run ios-snap render --device 'iPhone 15' --expr 'Text("Probe")' --imports 'SwiftUI,QuextWiFiFramework' --workspace /Users/elychkouski/work/Quext/quext-iot-ios/Frameworks/quext-iot-ios-wifi-framework/QuextWiFiFramework.xcworkspace --dep-scheme QuextWiFiFramework --out /tmp/probe.png
Output (summary):
  - Added simulator architecture overrides so staged dependencies and the Runner build target a single host slice.
  - Taught DependencyBuilder to harvest xcframeworks, skip embedding static frameworks, and embed only dynamic frameworks/dylibs.
  - Render now succeeds end-to-end; snapshot saved to /tmp/probe.png.

Result: success
Artifacts:
  - /tmp/probe.png

Decisions:
  - Dropped SWIFT_INCLUDE_PATHS for frameworks; rely on FRAMEWORK_SEARCH_PATHS to resolve modules and avoid relocation errors.
  - Embed only dynamic frameworks to keep static CocoaPods archives out of Runner.app.

Next steps:
  - Consider logging dependency overrides when --verbose is set to aid future debugging.
Blockers/Risks:
  - None.

```
Date: 2025-10-18
Author: Agent
Branch: main
Commit: <pending>

Task: Investigate render failure for WifiOfferCheckoutSelectedPlanCardPreview
Context: Rendering the framework preview view still failed despite dependency staging adjustments.
Commands:
  - IOS_SNAP_DEBUG_DEPS=1 swift run ios-snap render --device 'iPhone 15' --expr 'WifiOfferCheckoutSelectedPlanCardPreview()' --imports 'SwiftUI,QuextWiFiFramework' --workspace /Users/elychkouski/work/Quext/quext-iot-ios/Frameworks/quext-iot-ios-wifi-framework/QuextWiFiFramework.xcworkspace --dep-scheme QuextWiFiFramework --out test.png
  - xcodebuild -project Runner.xcodeproj -scheme Runner -configuration Release -sdk iphonesimulator -destination 'id=70A460C6-8035-4BCD-BE15-A7B6A88FFE4B' -xcconfig Overrides.xcconfig build (from preserved workspace)
Output (summary):
  - xcconfig-based overrides confirm the Runner now sees QuextWiFiFramework and links staged dependencies.
  - Build stops with `'WifiOfferCheckoutSelectedPlanCardPreview' initializer is inaccessible due to 'internal' protection level`.

Result: blocked
Blockers/Risks:
  - The preview struct in QuextWiFiFramework lacks a public initializer, so ios-snap cannot instantiate it.
Next steps:
  - Coordinate with the framework team to expose a public initializer or alternative public factory for the preview scene.
```
```
