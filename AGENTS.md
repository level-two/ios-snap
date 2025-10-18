# AGENTS.md — Working Rules for Agents in this Repo

Scope: This file applies to the entire repository. Follow these instructions whenever an agent is launched to work on ios-snap.

## Source of Truth
- Primary: `SPEC.md`
- Execution: `IMPLEMENTATION_PLAN.md`
- Guardrails: `docs/CODING_STYLE.md`, `docs/ARCHITECTURE.md`, `docs/CLI_REFERENCE.md`, `docs/BATCH_CONFIG.md`
- Progress artifacts: `CHECKLIST.md`, `DEVLOG.md`

Note: Guardrail documents live under `docs/`.

If any instruction here conflicts with a direct user/developer instruction in the session, the latter takes precedence.

## Startup Checklist (Every Session)
1) Read: `SPEC.md`, `IMPLEMENTATION_PLAN.md`, `CHECKLIST.md` (current milestone), and relevant docs for the phase.
2) Initialize your plan: use the plan tool with the current phase and next 2–3 concrete steps.
3) Open a DEVLOG entry (append) with date, branch (if applicable), task, commands to run, and expected outcomes.

## Iteration Loop (Granular & Testable)
- Before actions: send a brief preamble of what you’ll do next.
- Implement: make focused changes using the patch tool. Avoid unrelated edits.
- Validate: run the smallest specific verification for the change. If approval mode restricts commands, propose what to run and wait for approval.
- Update plan: mark completed steps and set next step to in_progress.
- Checklist: tick relevant items in `CHECKLIST.md` when verifiably done.
- Log: append key commands, outputs, and decisions to `DEVLOG.md`.

## Validation Policy
- Prefer targeted tests for the code you changed.
- Proactively run builds/tests in non-interactive or on-failure modes; in interactive modes, ask before long-running tasks.
- Keep simulator state clean: always clear status bar overrides and delete temp dirs on success.

## Coding & Safety Rules
- Keep changes minimal and aligned with `docs/CODING_STYLE.md`.
- Do not execute arbitrary shell derived from user snippet inputs. Treat `imports` and `expr` as string tokens for source injection only.
- Use argv arrays for shell invocations; never string-concatenate commands.
- Do not add licenses/headers unless asked. Do not commit or create branches unless explicitly requested.

## Files & Layout Expectations
- CLI: `Sources/ios-snap` (ArgumentParser subcommands, Shell helper).
- SnapshotKit: `Sources/SnapshotKit` (registry runtime).
- Runner template: `Templates/Runner` (tokenized RootView and RunnerApp).
- Examples & scripts: `Examples`, `Scripts/selftest.sh`.

## Phase Gates (Must Produce Artifacts)
- B: `ios-snap --help` shows subcommands.
- C: `ios-snap devices` prints available iOS simulators.
- E: Runner template builds for iphonesimulator.
- F: `ios-snap render --expr 'Text("Hello")' ...` writes a PNG to `--out`.
- G: `ios-snap list` prints registry ids; `--scene` renders.
- H: Batch YAML produces all outputs.

## When to Ask for Guidance
- Ambiguity about iOS deployment target, bundle id customization, or locale launch args.
- Requests to change public API/CLI contract established in `docs/CLI_REFERENCE.md`.

## Notes for Nested AGENTS.md
If you work inside subdirectories, check for more specific AGENTS.md files; the most deeply nested file takes precedence for files in its scope.
