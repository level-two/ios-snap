# Contributing

## Dev Setup
```
git clone <repo>
cd ios-snap
swift build
swift run ios-snap devices
```

## Branch & Commits
- Use feature branches: `feat/something`, `fix/whatever`.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:` ...).

## PR Checklist
- Added/updated docs where applicable.
- Commands validated locally; clear error messages.
- No string-based shell concatenation; argv arrays used.
- Exit codes mapped correctly.
- Logs helpful under `--verbose`, quiet otherwise.

## Code Review Checklist
- Arguments validated and surfaced with actionable errors.
- Shell calls use argv arrays; no string concatenation.
- Exit codes mapped correctly and tested.
- Temporary artifacts cleaned up on success.

