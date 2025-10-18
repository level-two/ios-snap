# Coding Style

## Swift (CLI & Runner)
- Swift 5.10+/Swift 6 ready.
- Prefer `struct` and `final class` for reference types.
- Error paths return descriptive `Error` enums; map to exit codes centrally.
- No force unwraps in CLI. In Runner, allow guarded force‑unwraps post‑layout only if unavoidable.
- Logging: concise, single‑line, prefixed with phase tags: `[sim]`, `[build]`, `[run]`, `[pull]`.

## CLI Behavior
- Predictable exit codes (see `docs/ARCHITECTURE.md`).
- `--verbose` toggles command echo and stderr passthrough.
- All file outputs are atomic (write to temp, then move).

## Shell & Processes
- Use a dedicated Shell helper that captures stdout, stderr, and status.
- Never build command strings via concatenation; use argv arrays `[String]`.
- Timeouts for long operations (boot, build) with progress dots.

## Filesystem
- Temp workdirs under `~/Library/Caches/ios-snap/<uuid>`; cleanup on success.
- Respect user paths; expand `~`.

## SwiftUI SnapshotKit
- Registry is a static dictionary `[String: () -> AnyView]`.
- Ids use `/` namespaces (e.g., `locks/default`).
- Provide shim when macros unavailable: `SnapshotRegistry.register("id") { AnyView(view) }`.
