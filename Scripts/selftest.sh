#!/usr/bin/env bash
# ios-snap self-test runner
# Executes the verification matrix defined in SPEC.md (Tests 1–6).

set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log() {
  printf '[selftest] %s\n' "$*"
}

log_cmd() {
  printf '[selftest]$'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "error: required tool '$1' not found on PATH"
    exit 1
  fi
}

assert_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    log "error: expected file not found: $path"
    exit 1
  fi
}

assert_png() {
  local path="$1"
  assert_file "$path"
  local signature
  signature="$(head -c 8 "$path" | hexdump -v -e '/1 "%02x"')"
  if [[ "$signature" != "89504e470d0a1a0a" ]]; then
    log "error: $path is not a PNG (signature $signature)"
    exit 1
  fi
}

checksum() {
  shasum -a 256 "$1" | awk '{print $1}'
}

assert_checksums_differ() {
  local lhs="$1"
  local rhs="$2"
  if [[ "$lhs" == "$rhs" ]]; then
    log "error: checksums unexpectedly match"
    exit 1
  fi
}

require_tool swift
require_tool xcrun
require_tool shasum
require_tool hexdump

OUT_DIR="${SELFTEST_OUT_DIR:-"$ROOT/screens/selftest"}"
mkdir -p "$OUT_DIR"

DEVICE_DEFAULT="${SELFTEST_DEVICE:-iPhone 15}"
HELLO_EXPR="$(cat <<'SWIFT'
({ () -> AnyView in
    struct SelfTestView: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            ZStack {
                backgroundColor.ignoresSafeArea()
                VStack(spacing: 24) {
                    Label(appearanceTitle, systemImage: isDark ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                    Text("appearance: \(appearanceTitle)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("dynamic type: \(contentSizeLabel)")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 28)
                        .fill(cardColor.gradient)
                        .frame(height: 180)
                        .overlay(
                            VStack(spacing: 16) {
                                Text("ios-snap self-test")
                                    .font(.headline)
                                    .foregroundStyle(isDark ? .white : .black)
                                ProgressView(value: isDark ? 0.75 : 0.35)
                                    .tint(accentColor)
                                    .scaleEffect(x: 1.3, y: 1.3)
                            }
                            .padding(36)
                        )
                        .shadow(color: accentColor.opacity(isDark ? 0.5 : 0.2), radius: 22, x: 0, y: 12)
                }
                .padding(36)
            }
        }

        private var isDark: Bool { colorScheme == .dark }

        private var appearanceTitle: String { isDark ? "dark" : "light" }

        private var contentSizeLabel: String {
            switch dynamicTypeSize {
            case .xSmall: return "XS"
            case .small: return "S"
            case .medium: return "M"
            case .large: return "L"
            case .xLarge: return "XL"
            case .xxLarge: return "XXL"
            case .xxxLarge: return "XXXL"
            case .accessibility1: return "AX1"
            case .accessibility2: return "AX2"
            case .accessibility3: return "AX3"
            case .accessibility4: return "AX4"
            case .accessibility5: return "AX5"
            @unknown default:
                return String(describing: dynamicTypeSize)
            }
        }

        private var backgroundColor: Color {
            isDark
                ? Color(red: 0.08, green: 0.07, blue: 0.16)
                : Color(red: 0.94, green: 0.97, blue: 1.00)
        }

        private var cardColor: Color {
            isDark
                ? Color(red: 0.18, green: 0.20, blue: 0.32)
                : Color(red: 0.98, green: 0.99, blue: 1.00)
        }

        private var accentColor: Color {
            isDark
                ? Color(red: 0.82, green: 0.62, blue: 1.00)
                : Color(red: 0.22, green: 0.36, blue: 0.84)
        }
    }

    return AnyView(SelfTestView())
}())
SWIFT
)"

if [[ -z "${IOS_SNAP_BIN:-}" ]]; then
  log "Building ios-snap (release)"
  log_cmd swift build -c release
  swift build -c release
  IOS_SNAP_BIN="$ROOT/.build/release/ios-snap"
else
  if [[ "$IOS_SNAP_BIN" != /* ]]; then
    IOS_SNAP_BIN="$ROOT/$IOS_SNAP_BIN"
  fi
fi

if [[ ! -x "$IOS_SNAP_BIN" ]]; then
  log "error: ios-snap binary not found at $IOS_SNAP_BIN"
  exit 1
fi

log "Using ios-snap binary: $IOS_SNAP_BIN"
log "Writing outputs under: $OUT_DIR"

## Test 1 — Hello world (light)
HELLO_LIGHT="$OUT_DIR/hello-light.png"
log "Test 1 — snippet hello (light)"
log_cmd "$IOS_SNAP_BIN" render --expr "$HELLO_EXPR" --imports SwiftUI --device "$DEVICE_DEFAULT" --out "$HELLO_LIGHT"
"$IOS_SNAP_BIN" render --expr "$HELLO_EXPR" --imports SwiftUI --device "$DEVICE_DEFAULT" --out "$HELLO_LIGHT"
assert_png "$HELLO_LIGHT"
HELLO_LIGHT_SHA="$(checksum "$HELLO_LIGHT")"

# Test 2 — Dark variant differs
HELLO_DARK="$OUT_DIR/hello-dark.png"
log "Test 2 — snippet hello (dark appearance)"
log_cmd "$IOS_SNAP_BIN" render --expr "$HELLO_EXPR" --imports SwiftUI --device "$DEVICE_DEFAULT" --appearance dark --out "$HELLO_DARK"
"$IOS_SNAP_BIN" render --expr "$HELLO_EXPR" --imports SwiftUI --device "$DEVICE_DEFAULT" --appearance dark --out "$HELLO_DARK"
assert_png "$HELLO_DARK"
HELLO_DARK_SHA="$(checksum "$HELLO_DARK")"
assert_checksums_differ "$HELLO_LIGHT_SHA" "$HELLO_DARK_SHA"

# Test 3 — Dynamic Type scaling
HELLO_AX="$OUT_DIR/hello-ax2.png"
log "Test 3 — snippet hello (AX2 content size)"
log_cmd "$IOS_SNAP_BIN" render --expr "$HELLO_EXPR" --imports SwiftUI --device "$DEVICE_DEFAULT" --content-size AX2 --out "$HELLO_AX"
"$IOS_SNAP_BIN" render --expr "$HELLO_EXPR" --imports SwiftUI --device "$DEVICE_DEFAULT" --content-size AX2 --out "$HELLO_AX"
assert_png "$HELLO_AX"
HELLO_AX_SHA="$(checksum "$HELLO_AX")"
assert_checksums_differ "$HELLO_LIGHT_SHA" "$HELLO_AX_SHA"

# Test 4 — Status bar override
HELLO_STATUS="$OUT_DIR/hello-status.png"
log "Test 4 — snippet hello (status bar override)"
log_cmd "$IOS_SNAP_BIN" render --expr "$HELLO_EXPR" --imports SwiftUI --device "$DEVICE_DEFAULT" --status-bar 'time=09:41 wifi=3 battery=100' --out "$HELLO_STATUS"
"$IOS_SNAP_BIN" render --expr "$HELLO_EXPR" --imports SwiftUI --device "$DEVICE_DEFAULT" --status-bar 'time=09:41 wifi=3 battery=100' --out "$HELLO_STATUS"
assert_png "$HELLO_STATUS"
HELLO_STATUS_SHA="$(checksum "$HELLO_STATUS")"
assert_checksums_differ "$HELLO_LIGHT_SHA" "$HELLO_STATUS_SHA"

# Test 5 — YAML batch
BATCH_OUTPUTS=(
  "$ROOT/screens/batch-snippet-hello.png"
  "$ROOT/screens/batch-snippet-hello-dark.png"
  "$ROOT/screens/batch-registry-hello.png"
  "$ROOT/screens/batch-registry-error.png"
)
log "Test 5 — batch rendering"
for path in "${BATCH_OUTPUTS[@]}"; do
  rm -f "$path"
done
log_cmd "$IOS_SNAP_BIN" batch --config "$ROOT/Examples/Snapshots.yml"
"$IOS_SNAP_BIN" batch --config "$ROOT/Examples/Snapshots.yml"
for path in "${BATCH_OUTPUTS[@]}"; do
  assert_png "$path"
done

# Test 6 — Registry mode list + render
log "Test 6 — registry mode list"
log_cmd "$IOS_SNAP_BIN" list --device "$DEVICE_DEFAULT" --snippet "$ROOT/Examples/Registry/Scenes.swift"
LIST_OUTPUT="$("$IOS_SNAP_BIN" list --device "$DEVICE_DEFAULT" --snippet "$ROOT/Examples/Registry/Scenes.swift")"
printf '%s\n' "$LIST_OUTPUT"
if ! printf '%s\n' "$LIST_OUTPUT" | grep -q 'demo/hello'; then
  log "error: registry output missing demo/hello"
  exit 1
fi
if ! printf '%s\n' "$LIST_OUTPUT" | grep -q 'demo/error'; then
  log "error: registry output missing demo/error"
  exit 1
fi

REGISTRY_OUT="$OUT_DIR/registry-demo-hello.png"
log "Test 6 — registry mode render"
log_cmd "$IOS_SNAP_BIN" render --scene demo/hello --device "$DEVICE_DEFAULT" --snippet "$ROOT/Examples/Registry/Scenes.swift" --out "$REGISTRY_OUT"
"$IOS_SNAP_BIN" render --scene demo/hello --device "$DEVICE_DEFAULT" --snippet "$ROOT/Examples/Registry/Scenes.swift" --out "$REGISTRY_OUT"
assert_png "$REGISTRY_OUT"

log "All tests passed. Outputs available in $OUT_DIR and screens/."
