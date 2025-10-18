# ios-snap Implementation Checklist

Use this as a quick, practical gate at each milestone. Check items off only when verifiably complete.

## Pre‑flight
- [ ] Xcode installed; `xcrun simctl` available
- [ ] iOS Simulator runtime installed (e.g., iOS 17+)
- [ ] Swift 5.10+ present (`swift --version`)
- [ ] `screens/` folder exists or is creatable

## Phase A — Scaffold
- [ ] `Package.swift` builds (no-op)
- [ ] Repo layout created (Sources, Templates, Examples, Scripts)

## Phase B — CLI Skeleton
- [ ] `ios-snap --help` prints
- [ ] Each subcommand `--help` prints
- [ ] Exit codes mapped for basic argument errors

## Phase C — Devices
- [x] `ios-snap devices` prints available iOS simulators
- [x] Output includes device name and UDID

## Phase D — Simulator Manager
- [x] Resolve UDID by device name works
- [x] Boot existing simulator works; waits until booted
- [x] Status bar override/clear helpers work

## Phase E — Runner Template
- [x] Runner project compiles for iphonesimulator (Release)
- [x] Token injection (imports/expr) works
- [x] Snippet file path injection works

## Phase F — Render Flow
- [x] Build, install, launch, capture, pull works end‑to‑end
- [x] Hello PNG created at `--out`
- [x] Status bar overrides applied/cleared

## Phase G — Registry‑mode
- [x] SnapshotRegistry API implemented
- [x] `ios-snap list` prints scene ids
- [x] `ios-snap render --scene` writes PNG

## Phase H — Batch
- [x] YAML parsed and validated (Yams)
- [x] All outputs created from Examples/Snapshots.yml
- [x] `--continue-on-error` behavior correct

## Phase I — Self-tests & Docs
- [x] `Scripts/selftest.sh` passes all tests
- [x] Docs updated and accurate (README, CLI_REFERENCE)
- [x] Troubleshooting covers common errors

## Phase J — SwiftPM Plugin
- [x] `swift package ios-snap --help` prints usage
- [x] Plugin forwards arguments and exit codes

## Phase J.5 — Refactoring & Best Practices
- [x] Split SRP files (RenderWorkflow decomposition; consider SimulatorManager layering)
- [x] Decompose long functions into private helpers; use `private`/`fileprivate` extensions
- [x] Introduce Command-pattern steps for render pipeline without changing behavior
- [x] Centralize error-to-exit-code mapping for new commands
- [x] Wrap long lines/argument arrays per style
- [x] Build + smoke checks pass; CLI outputs unchanged

## Final
- [ ] Temp dirs removed on success; retained with path on failure
- [ ] No global simulator state left dirty (status bar cleared)

## Phase K — External Dependencies
- [x] Flags parsed and validated: `--workspace`, `--project`, `--dep-scheme`, `--package`, `--product`
- [x] Building host schemes produces simulator artifacts into staging
- [x] Runner build injects search paths and `OTHER_LDFLAGS` without mutating the project
- [x] Snippet-mode renders a view from external framework
- [x] Batch accepts external fields and resolves paths relative to the config
- [x] (Optional) `--package/--product` builds and links SwiftPM products
