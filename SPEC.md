ios-snap — CLI Snapshotter for SwiftUI (Agent Implementation Spec)

Owner: Yauheni Lychkouski • Target platform: macOS + Xcode/iOS Simulator • Tooling: Swift, SwiftPM, Xcodebuild, simctl

This document is the single source of truth for implementing a CLI tool that renders SwiftUI views into PNG screenshots without walking an end‑to‑end UI flow. It defines goals, scope, modes, CLI, architecture, step‑by‑step tasks, examples, self‑tests, and acceptance criteria.

⸻

0) TL;DR Quick Start (Desired UX)

Snippet‑mode (zero integration)

ios-snap render \
  --expr 'LocksScreen(viewModel: .preview)' \
  --imports 'MyAppUI,MyAppMocks' \
  --device 'iPhone 15 Pro' \
  --appearance dark \
  --locale 'pl-PL' \
  --content-size XL \
  --orientation portrait \
  --status-bar 'time=09:41 wifi=3 cellular=4 battery=100' \
  --wait 0.25 \
  --out ./screens/locks-dark@iPhone15Pro.png

Or via file snippet:

ios-snap render --snippet ./Snapshots/Locks.swift --device 'iPhone 15' --out ./screens/locks.png

Where Snapshots/Locks.swift:

import SwiftUI
import MyAppUI
import MyAppMocks

public func makeView() -> some View {
    LocksScreen(viewModel: .preview)
}

Batch by YAML:

ios-snap batch --config ./Snapshots.yml

Registry‑mode (minimal integration)

// In your app UI module
import SwiftUI
import SnapshotKit
import MyAppUI
import MyAppMocks

@Snapshot("locks/default", size: .iPhone15Pro)
var locksDefault: some View { LocksScreen(viewModel: .preview) }

@Snapshot("locks/error", size: .iPhone15Pro)
var locksError: some View { LocksScreen(viewModel: .errorState) }

List and render:

ios-snap list
ios-snap render --scene 'locks/default' --appearance dark --locale 'pl-PL' --out ./screens/locks-default-dark.png


⸻

1) Goals & Non‑Goals

Goals
	•	Render SwiftUI views to PNG, similar to Previews, but via CLI and iOS Simulator runtime.
	•	Two modes:
	1.	Snippet‑mode: no code changes in the app; pass expression/imports or a snippet file.
	2.	Registry‑mode: optional tiny integration (SnapshotKit) to register scenes by id.
	•	Control device, dark/light, Dynamic Type, locale/region, orientation (visual), status bar, wait delay, output path.
	•	Batch/yaml runs for matrices of variants.
	•	CI‑friendly; deterministic; clear logging and exit codes.

Non‑Goals
	•	No UI automation/tapping (that’s XCUITest’s domain).
	•	No real hardware devices (simulator only).
	•	No dependence on third‑party build generators (e.g., XcodeGen) — we ship a minimal Runner.xcodeproj template in repo.

⸻

2) Deliverables
	1.	Binary: ios-snap (SwiftPM executable) with subcommands: render, batch, list, devices.
	2.	SwiftPM plugin (bonus): swift package ios-snap ... proxy to the same features.
	3.	SnapshotKit micro‑library (registry‑mode runtime + @Snapshot macro or simple registration API).
	4.	Runner template: minimal SwiftUI iOS app Xcode project used in snippet‑mode.
	5.	Examples: sample snippets, sample registry file, sample YAML batch.
	6.	Self‑tests: scripts to verify E2E on CI/macOS runner.

⸻

3) CLI Contract

Subcommands
	•	ios-snap render — render a single scene (snippet or registry id).
	•	ios-snap batch — render many scenes/variants from a YAML/JSON config.
	•	ios-snap list — list available registry scenes (registry‑mode only; graceful empty in snippet‑mode).
	•	ios-snap devices — list available simulator devices and runtimes.

Common flags

--device <name>            # e.g. 'iPhone 15 Pro' (required unless --udid specified)
--udid <sim-udid>          # prefer this if provided
--appearance <light|dark|auto>
--content-size <XS|S|M|L|XL|XXL|AX1|AX2|AX3|AX4|AX5>
--locale <xx-YY>           # e.g., pl-PL
--region <REGION>          # optional override
--orientation <portrait|landscape>
--background <#RRGGBB|clear>
--status-bar 'time=09:41 wifi=3 cellular=4 battery=100 state=charged'
--wait <seconds>           # delay before capture (default 0.2)
--scale <2|3>              # output scale; default = device
--out <path.png>           # output file path (required)
--verbose                  # debug logs

Snippet‑mode flags

--expr '<SwiftUI expression>'
--imports 'ModA,ModB,SwiftUI'     # modules to import; comma‑separated
--snippet <path.swift>            # alternative to --expr; must provide makeView()->some View

Registry‑mode flags

--scene '<id>'                    # e.g., 'locks/default'
--app-scheme '<XcodeScheme>'      # optional; defaults to Runner scheme in template or provided example app scheme
--workspace '<.xcworkspace>'      # optional; for integrated builds
--project '<.xcodeproj>'          # default: shipped Runner template for snippet‑mode

Batch config (YAML)

scenes:
  - id: locks
    imports: [MyAppUI, MyAppMocks]
    expr: "LocksScreen(viewModel: .preview)"
    variants:
      - device: "iPhone 15 Pro"
        appearance: light
        locale: en-US
        size: "393x852"         # optional absolute points; otherwise device default
        out: "screens/locks/en/light.png"
      - device: "iPhone 15 Pro"
        appearance: dark
        locale: pl-PL
        status_bar: "time=09:41 wifi=3 battery=100"
        out: "screens/locks/pl/dark.png"

global:
  content_size: L
  orientation: portrait
  wait: 0.25

Notes:
	•	If size is provided, the Runner window uses that point size (simulates orientation by swapping width/height if needed).
	•	For registry‑mode, each scene defines default size (via @Snapshot(... size:)). CLI flags can override.

⸻

4) Architecture

High‑level flow (both modes)
	1.	Prepare simulator: ensure device exists (create/boot if needed), set status bar overrides.
	2.	Assemble Runner:
	•	Snippet‑mode: copy Templates/Runner to temp dir, inject imports/expr or snippet file.
	•	Registry‑mode: build the app that exposes SnapshotRegistry.
	3.	Build with xcodebuild -sdk iphonesimulator.
	4.	Launch with simctl launch passing env/args (appearance, locale, content size, size, wait, out path).
	5.	Runner renders SwiftUI view in UIHostingController and writes PNG to app Documents.
	6.	CLI pulls file via simctl get_app_container .../Documents to desired --out path.
	7.	Reset status bar overrides.

Runner responsibilities
	•	Read env vars and configure:
	•	SNAP_APPEARANCE=light|dark|auto
	•	SNAP_CONTENT_SIZE=...
	•	SNAP_SIZE=WIDTHxHEIGHT (points)
	•	SNAP_BACKGROUND=#RRGGBB|clear
	•	SNAP_OUT_FILENAME=name.png
	•	SNAP_WAIT=0.2
	•	SNAP_SCENE_ID=locks/default (registry‑mode)
	•	Build the SwiftUI hierarchy (expr or registry), mount into a full‑screen window, RunLoop tick, capture, write PNG, terminate.

Status bar control
	•	Use xcrun simctl status_bar <udid> override ... before launch; clear with clear after capture.

⸻

5) Step‑by‑Step Implementation Plan

The agent should work top‑down, committing at each step with runnable milestones.

Phase A — Repo Scaffold
	•	Create repo ios-snap/ with:

Package.swift
Sources/
  ios-snap/                # CLI executable using ArgumentParser
  SnapshotKit/             # Registry runtime (library)
Templates/
  Runner/Runner.xcodeproj  # Minimal SwiftUI app project template
  Runner/Runner/           # Sources for Runner
Examples/
  Snippets/Locks.swift
  Snapshots.yml
Scripts/
  selftest.sh
README.md

	•	Add .gitignore for /.build, /DerivedData, /Temp, /screens.

Phase B — CLI skeleton (ArgumentParser)
	•	Implement subcommands with structs: RenderCommand, BatchCommand, ListCommand, DevicesCommand.
	•	Implement argument parsing and validation.
	•	Implement logging helper and shell runner (capture stdout/stderr; return exit codes).

Phase C — Simulator management
	•	devices subcommand: run xcrun simctl list --json devices and pretty‑print available devices; filter to available/iOS only.
	•	Utilities:
	•	Resolve UDID by device name (pick latest available runtime).
	•	Create simulator if missing: xcrun simctl create <name> <deviceTypeId> <runtimeId>.
	•	Boot if needed: xcrun simctl boot <udid> and wait until booted.

Phase D — Runner template & injection (snippet‑mode)
	•	Ship Templates/Runner containing:
	•	RunnerApp.swift (reads env; mounts RootView())
	•	RootView.swift with marker tokens:
	•	//__SNAP_IMPORTS__ → replaced with import lines
	•	//__SNAP_EXPR__ → replaced with the SwiftUI expression or a call to makeView() from snippet file
	•	Info.plist minimal; iOS 17+ target; SwiftUI lifecycle; Supports multiple windows = NO.
	•	On render in snippet‑mode:
	1.	Copy template to temp work dir.
	2.	If --snippet supplied: copy file into Runner/, and set expr to makeView() automatically.
	3.	Replace tokens in RootView.swift.
	4.	Generate Config.swift with compile‑time defaults (optional; most settings via env).

Phase E — Build & launch
	•	Build:

xcodebuild -project Runner.xcodeproj -scheme Runner \
  -sdk iphonesimulator -destination "id=<UDID>" \
  -configuration Release -derivedDataPath <temp>/DerivedData \
  build

	•	Install & launch:

APP_PATH=$(xcrun simctl get_app_container <UDID> com.example.Runner data 2>/dev/null || true)
# Or use .app from DerivedData/Build/Products/Release-iphonesimulator/Runner.app
xcrun simctl install <UDID> <path_to_app>
# Status bar override (optional)
xcrun simctl status_bar <UDID> override --time 09:41 --wifiBars 3 --cellularBars 4 --batteryLevel 100 --batteryState charged
# Launch with env
xcrun simctl launch --terminate-running-process --console <UDID> com.example.Runner \
  SNAP_APPEARANCE=dark SNAP_CONTENT_SIZE=XL SNAP_SIZE=393x852 SNAP_WAIT=0.25 SNAP_OUT_FILENAME=__snap.png

	•	After exit, pull file:

APP_DOCS=$(xcrun simctl get_app_container <UDID> com.example.Runner data)/Documents
cp "$APP_DOCS/__snap.png" ./out.png
# Clear status bar
xcrun simctl status_bar <UDID> clear

Phase F — Runner capture code
	•	Inside Runner:
	•	Build RootView() from expr/scene.
	•	Mount into UIHostingController; create UIWindow of requested size.
	•	Apply appearance (override interface style), Dynamic Type (override trait), background.
	•	Allow a short RunLoop.main.run(until: Date().addingTimeInterval(wait)) for layout.
	•	Render window to UIImage using UIGraphicsImageRenderer and write PNG to Documents/<SNAP_OUT_FILENAME>.
	•	Call exit(0).

Phase G — Registry‑mode (SnapshotKit)
	•	Implement SnapshotRegistry:
	•	Static var scenes: [String: () -> AnyView].
	•	API: SnapshotRegistry.register(_ id: String, builder: @escaping () -> AnyView).
	•	Provide a tiny property‑wrapper or macro mimic:
	•	If macro is non‑trivial, simply ask users to call SnapshotRegistry.register("id") { AnyView(view) } in a dedicated file guarded by #if DEBUG && canImport(SnapshotKit).
	•	Runner in registry‑mode reads SNAP_SCENE_ID and fetches the view; if not found → log and exit(2).
	•	ios-snap list launches a small helper (or scans a generated JSON index) to print scene IDs. Simpler: compile a tiny ListScenes target that prints registry contents at runtime.

Phase H — Batch mode
	•	Parse YAML (use Yams via SwiftPM) or JSON (Foundation).
	•	Iterate variants, invoke the same internal flow as render.
	•	Aggregate results, stop on first failure by default; optional --continue-on-error.

Phase I — SwiftPM plugin (bonus)
	•	Create a command plugin IOSSnapPlugin that shells out to the built ios-snap binary with passed args.
	•	Usage:

swift package ios-snap --scene 'locks/default' --device 'iPhone 15'


⸻

6) Runner Code Sketches (key parts)

Tokenized RootView template (snippet‑mode)

// RootView.swift — template with tokens
//__SNAP_IMPORTS__
import SwiftUI

struct RootView: View {
    var body: some View {
        //__SNAP_EXPR__
    }
}

App entry reading env and capturing

import SwiftUI
import UIKit

@main
struct RunnerApp: App {
    var body: some Scene {
        WindowGroup {
            RootHost()
                .ignoresSafeArea()
        }
    }
}

struct RootHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let root = RootView()
        let host = UIHostingController(rootView: root)

        let window = UIWindow(frame: desiredFrame())
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()

        applyAppearance(window)
        applyDynamicType(host)
        setBackground(window)

        let wait = env("SNAP_WAIT").flatMap(Double.init) ?? 0.2
        RunLoop.main.run(until: Date().addingTimeInterval(wait))

        DispatchQueue.main.async {
            let image = window.snapshot()
            savePNG(image)
            exit(0)
        }
        return UIViewController()
    }
    func updateUIViewController(_: UIViewController, context: Context) {}
}

private func env(_ k: String) -> String? { ProcessInfo.processInfo.environment[k] }

private func desiredFrame() -> CGRect {
    if let sizeStr = env("SNAP_SIZE"),
       let w = Double(sizeStr.split(separator: "x")[safe: 0] ?? ""),
       let h = Double(sizeStr.split(separator: "x")[safe: 1] ?? "") {
        return CGRect(x: 0, y: 0, width: w, height: h)
    }
    // fallback to device screen
    return UIScreen.main.bounds
}

private func applyAppearance(_ window: UIWindow) {
    switch env("SNAP_APPEARANCE")?.lowercased() {
    case "dark": window.overrideUserInterfaceStyle = .dark
    case "light": window.overrideUserInterfaceStyle = .light
    default: break
    }
}

private func applyDynamicType(_ host: UIHostingController<RootView>) {
    let map: [String: UIContentSizeCategory] = [
        "XS": .extraSmall, "S": .small, "M": .medium, "L": .large, "XL": .extraLarge,
        "XXL": .extraExtraExtraLarge, "AX1": .accessibilityMedium, "AX2": .accessibilityLarge,
        "AX3": .accessibilityExtraLarge, "AX4": .accessibilityExtraExtraLarge, "AX5": .accessibilityExtraExtraExtraLarge
    ]
    if let key = env("SNAP_CONTENT_SIZE"), let cat = map[key] {
        host.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: cat), forChild: host)
    }
}

private func setBackground(_ window: UIWindow) {
    if let bg = env("SNAP_BACKGROUND"), bg.lowercased() != "clear" {
        window.backgroundColor = UIColor(hex: bg) ?? .systemBackground
    }
}

extension UIWindow {
    func snapshot() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { ctx in layer.render(in: ctx.cgContext) }
    }
}

private func savePNG(_ image: UIImage) {
    let name = env("SNAP_OUT_FILENAME") ?? "__snap.png"
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    if let data = image.pngData() { try? data.write(to: url) }
}

extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xff)/255.0,
                  green: CGFloat((v >> 8) & 0xff)/255.0,
                  blue: CGFloat(v & 0xff)/255.0, alpha: 1)
    }
}

extension Collection { subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil } }

Orientation note: we simulate by SNAP_SIZE width/height swap in CLI when --orientation=landscape. Status bar orientation may remain portrait — acceptable for UI catalog shots.

⸻

7) Self‑Tests & Verification

Create Scripts/selftest.sh to run end‑to‑end checks. The agent must ensure the following pass locally (macOS runner with Xcode):

Test 1 — Hello world (snippet)
	•	Cmd:

ios-snap render --expr 'Text("Hello")\n  .padding()\n  .font(.system(size: 24, weight: .bold))' \
  --imports 'SwiftUI' \
  --device 'iPhone 15' \
  --appearance light \
  --out ./screens/hello.png

	•	Verify file exists and is PNG; width/height equals device points × scale.

Test 2 — Dark vs Light differ
	•	Render same view with --appearance dark to hello-dark.png.
	•	Verify SHA256 hashes differ.

Test 3 — Dynamic Type scaling
	•	Render --content-size AX2; visually larger text; optional pixel‑count diff vs base.

Test 4 — Status bar override
	•	Set --status-bar 'time=09:41 wifi=3 battery=100' and confirm pixels in top region differ from base (basic histogram or filesize check).

Test 5 — YAML batch
	•	Run ios-snap batch --config Examples/Snapshots.yml and confirm all files created.

Test 6 — Registry‑mode listing and render
	•	Build example Registry app with two scenes.
	•	ios-snap list prints scene ids.
	•	Render scene id to file; verify exists.

Exit codes
	•	0 on success; non‑zero on build/launch/capture errors. CLI prints last failing step.

⸻

8) Acceptance Criteria (Definition of Done)
	•	ios-snap devices lists available iOS simulators.
	•	ios-snap render --expr ... produces a PNG at --out within ≤ 20s on a cold boot.
	•	--imports resolves modules; readable error if a module fails to import.
	•	Appearance, content size, size, wait, background, status bar flags affect output.
	•	YAML batch works and stops on first failure by default.
	•	Registry‑mode: a demo project can register scenes; list shows them; render --scene works.
	•	CI instructions included and green on a macOS runner with an iOS runtime.
	•	No global user state is left dirty (status bar override cleared; temp dirs removed).

⸻

9) Implementation Checklist (for the Agent)
	•	Create repo scaffold and Package.swift.
	•	Add ArgumentParser dependency; implement CLI skeleton.
	•	Implement shell runner and JSON helpers.
	•	Add Templates/Runner minimal SwiftUI app; expose bundle id com.example.Runner.
	•	Implement token injection for imports/expr or snippet file.
	•	Implement simulator manager: resolve/create/boot device; status bar override/clear.
	•	Build runner for given UDID; install; launch with env; wait; fetch Documents; copy PNG to --out.
	•	Implement YAML parser and batch execution.
	•	Implement SnapshotKit: registry API + demo scenes; list support.
	•	Add selftests script and sample Examples.
	•	Write README with quick start and troubleshooting.

⸻

10) Troubleshooting & Gotchas
	•	Blank images: increase --wait (animations/network/layout) or ensure view doesn’t depend on onAppear async.
	•	Module import errors: ensure target builds for iphonesimulator; add to --imports.
	•	Locale/region: prefer passing -AppleLanguages and -AppleLocale via simctl launch arguments if app logic depends on them. (Optionally add in Runner.)
	•	Status bar: available only on iOS 13+ simulators; always clear after.
	•	Orientation: we simulate via size; don’t rely on system bars orientation.
	•	Simulators missing: use xcrun simctl runtime add or open Xcode to install runtimes; CLI should give a clear error.

⸻

11) CI Notes
	•	Use a macOS runner with Xcode (e.g., GitHub Actions macos-14 w/ Xcode 16.x).
	•	Pre‑create a simulator device (cache step) for speed; or let CLI create on demand.
	•	Cache DerivedData between runs for faster incremental builds if scenes change often.

⸻

12) Nice‑to‑Haves (post‑MVP)
	•	Multi‑scale outputs (@2x/@3x in one go).
	•	Automatic cropping/padding; background blur.
	•	Overlay reference diffs (snapshot testing).
	•	Per‑scene JSON fixtures injection.
	•	Accessibility tree dump alongside PNG.

⸻

13) Ready‑to‑Use Commands (copy/paste)

# List devices
ios-snap devices

# Simple snippet render
ios-snap render --expr 'Text("Hello")' --imports 'SwiftUI' \
  --device 'iPhone 15' --out ./screens/hello.png

# With status bar and dark mode
ios-snap render --expr 'LocksScreen(viewModel: .preview)' \
  --imports 'MyAppUI,MyAppMocks' --device 'iPhone 15 Pro' \
  --appearance dark --status-bar 'time=09:41 wifi=3 battery=100' \
  --out ./screens/locks-dark.png

# Batch from YAML
ios-snap batch --config ./Snapshots.yml

# Registry list + render
ios-snap list
ios-snap render --scene 'locks/default' --device 'iPhone 15' --out ./screens/locks-default.png

⸻

14) External Dependencies (Phase K)

Goal
	•	Let the template Runner build and link external frameworks/products so snippet/registry can render views from multi-module app codebases.

CLI (planned flags)
	•	`--workspace <.xcworkspace>` or `--project <.xcodeproj>`
	•	`--dep-scheme <Name>` (repeatable) — build one or more schemes for `iphonesimulator` and stage outputs
	•	`--package <path>` + `--product <Name>` (repeatable) — build SwiftPM products by running `xcodebuild` inside the package root for `iphonesimulator` (scheme inferred from the manifest)

Build Strategy
	•	Build external artifacts into a staging folder under the runner workspace.
	•	Inject build settings at xcodebuild time: `FRAMEWORK_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, `SWIFT_INCLUDE_PATHS`, `OTHER_LDFLAGS`.
	•	Do not mutate `.pbxproj`.

Constraints
	•	Artifacts must target `iphonesimulator`.
	•	Swift module compatibility benefits from `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`.
