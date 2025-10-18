# Testing & Verification

## Self‑Tests (`Scripts/selftest.sh`)
1. Snippet baseline renders to `screens/selftest/hello-light.png`.
2. Dark variant hash differs from the baseline PNG.
3. Dynamic Type (`--content-size AX2`) hash differs from the baseline.
4. Status bar override hash differs from the baseline.
5. Batch config (`Examples/Snapshots.yml`) creates `screens/batch-*.png`.
6. Registry mode lists `demo/hello`, `demo/error` and renders `demo/hello` to `screens/selftest/registry-demo-hello.png`.

The script builds the release binary unless `IOS_SNAP_BIN` is provided. Override the simulator with `SELFTEST_DEVICE` and the output directory with `SELFTEST_OUT_DIR`. Outputs are overwritten on each run so you can diff results easily.

## Manual Checks
- Orientation emulation via `--size` and `--orientation` swaps.
- Background color applied.
- `--wait` influences async `.onAppear` content.

## Determinism
- Fix time/network via status bar + mock data.
- Avoid non‑deterministic animations (disable or wait long enough).

