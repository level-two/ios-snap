# Troubleshooting

## Build fails (exit 2)
- Ensure modules in `--imports` build for iphonesimulator.
- Open the generated Runner project under `~/Library/Caches/ios-snap/.../Runner.xcodeproj` to inspect.

## No such device / boot timeout (exit 3)
- Install iOS runtime via Xcode Preferences → Platforms.
- Run `xcrun simctl list` to verify devices and runtimes.

## Black/empty image (exit 5)
- Increase `--wait`.
- Ensure view does not depend on unavailable environment (e.g., ScenePhase).

## Status bar not applying
- Use iOS 13+ simulators.
- Clear overrides after failures: `xcrun simctl status_bar <udid> clear`.
- Keep in mind the simulator overlay is not captured; ios-snap renders a synthetic status bar inside the runner using the values from `--status-bar`.

## Locale not applied
- Prefer passing languages/locale via simctl launch arguments (`-AppleLanguages`, `-AppleLocale`) in Runner if app logic depends on them.

## `swift build` reports `permissionDenied`
- Ensure the build runs outside of restricted sandboxes; SwiftPM needs access to `$HOME/Library/Developer`.
- Verify `xcode-select -p` points at an installed Xcode and rerun `sudo xcode-select -s /Applications/Xcode.app` if needed.

## `swift package ios-snap render` fails with `Operation not permitted`
- SwiftPM command plugins run in a sandbox that blocks simulator writes (e.g., `.tmp/launch_console` FIFOs).
- Re-run with `swift package --disable-sandbox ios-snap render ...` or add targeted `--allow-reading/--allow-writing` flags for `$HOME/Library/Developer`.
- Alternatively, build the binary (`swift build -c release`) and run `./.build/release/ios-snap` directly outside the sandbox.

