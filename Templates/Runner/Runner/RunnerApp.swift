import SwiftUI
import UIKit


@main
struct RunnerApp: App {
    private let config: RunnerConfig

    init() {
        let env = ProcessInfo.processInfo.environment
        do {
            config = try RunnerConfig.load()
        } catch {
            RunnerExit.fail("Failed to load runner configuration: \(error)")
        }
        if let command = env["SNAP_COMMAND"], command.lowercased() == "list" {
            SnapshotListCommand.run(config: config)
        }
    }

    var body: some Scene {
        WindowGroup {
            SnapshotRenderer(config: config)
                .environment(\.dynamicTypeSize, config.dynamicTypeSize ?? .large)
                .preferredColorScheme(config.colorScheme)
        }
    }
}

// MARK: - Renderer Container

struct SnapshotRenderer: UIViewControllerRepresentable {
    let config: RunnerConfig

    func makeUIViewController(context: Context) -> SnapshotHostViewController {
        SnapshotHostViewController(config: config)
    }

    func updateUIViewController(_ uiViewController: SnapshotHostViewController, context: Context) {}
}

final class SnapshotHostViewController: UIViewController {
    private var config: RunnerConfig
    private let hostingController: UIHostingController<RootWrapperView>
    private var hasScheduledCapture = false

    init(config: RunnerConfig) {
        self.config = config
        self.hostingController = UIHostingController(rootView: RootWrapperView(config: config))
        super.init(nibName: nil, bundle: nil)
#if os(iOS)
        hostingController.setNeedsStatusBarAppearanceUpdate()
#endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = config.backgroundColor ?? .systemBackground
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        if let size = config.targetSize {
            NSLayoutConstraint.activate([
                hostingController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                hostingController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                hostingController.view.widthAnchor.constraint(equalToConstant: size.width),
                hostingController.view.heightAnchor.constraint(equalToConstant: size.height),
            ])
            view.bounds = CGRect(origin: .zero, size: size)
            view.frame = view.bounds
        } else {
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hostingController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                hostingController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hostingController.view.invalidateIntrinsicContentSize()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTraitOverrides()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleCaptureIfNeeded()
    }

    private func applyTraitOverrides() {
        // Avoid window-wide side effects (undo any prior global override)
        view.window?.overrideUserInterfaceStyle = .unspecified

        var traits: [UITraitCollection] = []

        if let style = config.appearanceStyle {
            switch style {
            case .light, .dark:
                // Force just the child to light/dark
                traits.append(UITraitCollection(userInterfaceStyle: style))
            case .unspecified:
                // Follow system — do NOT add a style trait
                break
            @unknown default:
                break
            }
        }

        if let size = config.contentSizeCategory {
            traits.append(UITraitCollection(preferredContentSizeCategory: size))
        }

        // Apply / clear the override for the child
        if traits.isEmpty {
            setOverrideTraitCollection(nil, forChild: hostingController) // clears previous overrides
        } else {
            setOverrideTraitCollection(UITraitCollection(traitsFrom: traits), forChild: hostingController)
        }
    }

    private func scheduleCaptureIfNeeded() {
        guard !hasScheduledCapture else { return }
        hasScheduledCapture = true
        let delay = max(0, config.wait)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.captureSnapshot()
        }
    }

    private func captureSnapshot() {
        guard let hostView = hostingController.view else {
            RunnerExit.fail("Hosting controller view unavailable for capture.")
        }

        hostView.layoutIfNeeded()

        let captureSize: CGSize
        if let explicit = config.targetSize {
            captureSize = explicit
        } else {
            let boundsSize = hostView.bounds.size
            if boundsSize.width > 0 && boundsSize.height > 0 {
                captureSize = boundsSize
            } else {
                let intrinsic = hostView.intrinsicContentSize
                let valid = intrinsic.width.isFinite && intrinsic.height.isFinite && intrinsic.width > 0 && intrinsic.height > 0
                captureSize = valid ? intrinsic : CGSize(width: 393, height: 852)
            }
        }

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = UIScreen.main.scale
        let backgroundAlpha = config.backgroundColor?.cgColor.alpha ?? 0
        rendererFormat.opaque = backgroundAlpha >= 1.0

        let renderBounds = CGRect(origin: .zero, size: captureSize)
        let renderer = UIGraphicsImageRenderer(size: captureSize, format: rendererFormat)
        let image = renderer.image { _ in
            let previousBounds = hostView.bounds
            let previousFrame = hostView.frame
            hostView.bounds = renderBounds
            hostView.frame = renderBounds
            hostView.drawHierarchy(in: renderBounds, afterScreenUpdates: true)
            hostView.bounds = previousBounds
            hostView.frame = previousFrame
        }

        do {
            try SnapshotWriter.write(image: image, filename: config.outputFilename)
            RunnerExit.success()
        } catch {
            RunnerExit.fail("Failed to write snapshot: \(error)")
        }
    }
}

// MARK: - Root Wrapper

struct RootWrapperView: View {
    let config: RunnerConfig

    var body: some View {
        Group {
            if let status = config.statusBarOverride, config.targetSize == nil {
                VStack(spacing: 0) {
                    RunnerStatusBarOverlay(status: status, appearanceStyle: config.appearanceStyle)
                    baseContent
                }
            } else {
                baseContent
            }
        }
        .modifier(IgnoreSafeAreaIfNeeded(shouldIgnore: config.targetSize == nil))
    }

    private var baseContent: some View {
        RootView(config: config)
            .frame(width: config.targetSize?.width, height: config.targetSize?.height)
            .background(backgroundColor)
    }

    private var backgroundColor: Color {
        guard let color = config.backgroundColor else {
            return .clear
        }
        return Color(color)
    }
}

private struct IgnoreSafeAreaIfNeeded: ViewModifier {
    let shouldIgnore: Bool

    func body(content: Content) -> some View {
        if shouldIgnore {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

// MARK: - Configuration & Helpers

struct RunnerStatusBarOverlay: View {
    let status: RunnerStatusBarPresentation
    let appearanceStyle: UIUserInterfaceStyle?

    private var style: OverlayStyle {
        switch explicitStyle ?? appearanceStyle {
        case .dark:
            return OverlayStyle(
                background: Color.black.opacity(0.72),
                foreground: .white,
                secondary: Color.white.opacity(0.7)
            )
        default:
            return OverlayStyle(
                background: Color.white.opacity(0.9),
                foreground: .black,
                secondary: Color.black.opacity(0.6)
            )
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            style.background
            HStack(spacing: 16) {
                Text(status.time ?? "09:41")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                Spacer(minLength: 12)

                if let carrier = status.carrierName {
                    Text(carrier.uppercased())
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(style.secondary)
                }

                if let data = status.dataNetwork {
                    Text(data.uppercased())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(style.secondary)
                }

                statusStack
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Rectangle()
                .fill(style.foreground.opacity(0.1))
                .frame(height: 0.5)
        }
        .frame(height: 44)
    }

    private var explicitStyle: UIUserInterfaceStyle? {
        guard let token = status.styleToken else { return nil }
        switch token {
        case "lightcontent":
            return .dark
        case "darkcontent":
            return .light
        default:
            return nil
        }
    }

    @ViewBuilder
    private var statusStack: some View {
        HStack(spacing: 12) {
            if let wifi = status.wifiBars {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                    Text("\(clamp(value: wifi, max: 3))")
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(style.foreground)
            }

            if let cellular = status.cellularBars {
                HStack(spacing: 4) {
                    Image(systemName: "cellularbars")
                    Text("\(clamp(value: cellular, max: 4))")
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(style.foreground)
            }

            if let bluetooth = status.bluetoothState {
                Image(systemName: bluetoothIcon(bluetooth))
                    .foregroundStyle(style.foreground)
            }

            if let batteryLevel = status.batteryLevel {
                HStack(spacing: 4) {
                    Image(systemName: batterySymbol(for: batteryLevel, state: status.batteryState))
                    Text("\(batteryLevel)%")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(style.foreground)
            }
        }
    }

    private func clamp(value: Int, max upper: Int) -> Int {
        max(0, min(upper, value))
    }

    private func batterySymbol(for level: Int, state: String?) -> String {
        let clamped = max(0, min(100, level))
        if let state, state.lowercased() == "charging" || state.lowercased() == "charged" {
            return "battery.100.bolt"
        }
        switch clamped {
        case 0..<15: return "battery.0"
        case 15..<45: return "battery.25"
        case 45..<75: return "battery.50"
        case 75..<95: return "battery.75"
        default: return "battery.100"
        }
    }

    private func bluetoothIcon(_ state: String) -> String {
        switch state.lowercased() {
        case "on", "visible": return "bolt.horizontal.fill"
        case "connected": return "bolt.horizontal.circle.fill"
        default: return "bolt.horizontal"
        }
    }

    private struct OverlayStyle {
        let background: Color
        let foreground: Color
        let secondary: Color
    }
}

struct RunnerStatusBarPresentation {
    private let values: [String: String]

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var parsed: [String: String] = [:]
        for token in trimmed.split(whereSeparator: \.isWhitespace) {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            parsed[parts[0].lowercased()] = parts[1]
        }

        guard !parsed.isEmpty else { return nil }
        self.values = parsed
    }

    var time: String? { values["time"] }
    var wifiBars: Int? { values["wifi"].flatMap(Int.init) }
    var cellularBars: Int? { values["cellular"].flatMap(Int.init) }
    var dataNetwork: String? { values["data"] ?? values["network"] ?? values["mode"] }
    var batteryLevel: Int? { values["battery"].flatMap(Int.init) }
    var batteryState: String? { values["state"] }
    var carrierName: String? { values["carrier"] }
    var bluetoothState: String? { values["bluetooth"] }
    var styleToken: String? { values["style"]?.lowercased() }
}

struct RunnerConfig {
    let appearanceStyle: UIUserInterfaceStyle?
    let contentSizeCategory: UIContentSizeCategory?
    let dynamicTypeSize: DynamicTypeSize?
    let backgroundColor: UIColor?
    let wait: TimeInterval
    let targetSize: CGSize?
    let outputFilename: String
    let sceneID: String?
    let statusBarOverride: RunnerStatusBarPresentation?

    static func load() throws -> RunnerConfig {
        let env = ProcessInfo.processInfo.environment
        let sceneID = env["SNAP_SCENE_ID"].flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var appearanceStyle: UIUserInterfaceStyle?

        if let rawAppearance = env["SNAP_APPEARANCE"], !rawAppearance.isEmpty {
            switch rawAppearance.lowercased() {
            case "light": appearanceStyle = .light
            case "dark": appearanceStyle = .dark
            case "auto": appearanceStyle = .unspecified
            default: throw RunnerConfigError.invalidAppearance(rawAppearance)
            }
        }

        var contentCategory: UIContentSizeCategory?
        var dynamicTypeSize: DynamicTypeSize?
        if let rawContentSize = env["SNAP_CONTENT_SIZE"], !rawContentSize.isEmpty {
            guard let parsedCategory = UIContentSizeCategory(fromSnapValue: rawContentSize) else {
                throw RunnerConfigError.invalidContentSize(rawContentSize)
            }
            contentCategory = parsedCategory
            dynamicTypeSize = DynamicTypeSize(from: parsedCategory)
        }

        var targetSize: CGSize?
        if let rawSize = env["SNAP_SIZE"], !rawSize.isEmpty {
            guard let parsedSize = CGSize(fromSnapValue: rawSize) else {
                throw RunnerConfigError.invalidSize(rawSize)
            }
            targetSize = parsedSize
        } else if let size = sceneID.flatMap({ SnapshotRegistry.scene(for: $0)?.size }) {
            targetSize = CGSize(width: size.width, height: size.height)
        }

        let wait: TimeInterval
        if let rawWait = env["SNAP_WAIT"], !rawWait.isEmpty {
            guard let parsedWait = TimeInterval(rawWait) else {
                throw RunnerConfigError.invalidWait(rawWait)
            }
            wait = parsedWait
        } else {
            wait = 0.2
        }

        let backgroundColor: UIColor?
        if let rawBackground = env["SNAP_BACKGROUND"], !rawBackground.isEmpty {
            guard let parsedColor = UIColor(fromSnapHex: rawBackground) else {
                throw RunnerConfigError.invalidBackground(rawBackground)
            }
            backgroundColor = parsedColor
        } else {
            backgroundColor = nil
        }

        let outputFilename = env["SNAP_OUT_FILENAME"].flatMap { !$0.isEmpty ? $0 : nil } ?? "__snap.png"
        let statusBarOverride = env["SNAP_STATUS_BAR"].flatMap { RunnerStatusBarPresentation(rawValue: $0) }

        return RunnerConfig(
            appearanceStyle: appearanceStyle,
            contentSizeCategory: contentCategory,
            dynamicTypeSize: dynamicTypeSize,
            backgroundColor: backgroundColor,
            wait: wait,
            targetSize: targetSize,
            outputFilename: outputFilename,
            sceneID: sceneID,
            statusBarOverride: statusBarOverride
        )
    }
}

extension RunnerConfig {
    var colorScheme: ColorScheme? {
        guard let appearanceStyle else { return nil }
        switch appearanceStyle {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }
}

enum RunnerConfigError: Error, CustomStringConvertible {
    case invalidAppearance(String)
    case invalidContentSize(String)
    case invalidSize(String)
    case invalidWait(String)
    case invalidBackground(String)

    var description: String {
        switch self {
        case .invalidAppearance(let value):
            return "Invalid SNAP_APPEARANCE value '\(value)'. Expected light|dark|auto."
        case .invalidContentSize(let value):
            return "Invalid SNAP_CONTENT_SIZE value '\(value)'."
        case .invalidSize(let value):
            return "Invalid SNAP_SIZE value '\(value)'. Expected format WIDTHxHEIGHT."
        case .invalidWait(let value):
            return "Invalid SNAP_WAIT value '\(value)'."
        case .invalidBackground(let value):
            return "Invalid SNAP_BACKGROUND value '\(value)'. Expected #RRGGBB or 'clear'."
        }
    }
}

extension UIContentSizeCategory {
    init?(fromSnapValue value: String) {
        let normalized = value.uppercased()
        switch normalized {
        case "XS": self = .extraSmall
        case "S": self = .small
        case "M": self = .medium
        case "L": self = .large
        case "XL": self = .extraLarge
        case "XXL": self = .extraExtraLarge
        case "AX1": self = .accessibilityMedium
        case "AX2": self = .accessibilityLarge
        case "AX3": self = .accessibilityExtraLarge
        case "AX4": self = .accessibilityExtraExtraLarge
        case "AX5": self = .accessibilityExtraExtraExtraLarge
        default: return nil
        }
    }
}

extension DynamicTypeSize {
    init?(from category: UIContentSizeCategory) {
        switch category {
        case .extraSmall: self = .xSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .extraLarge: self = .xLarge
        case .extraExtraLarge: self = .xxLarge
        case .extraExtraExtraLarge: self = .xxxLarge
        case .accessibilityMedium: self = .accessibility1
        case .accessibilityLarge: self = .accessibility2
        case .accessibilityExtraLarge: self = .accessibility3
        case .accessibilityExtraExtraLarge: self = .accessibility4
        case .accessibilityExtraExtraExtraLarge: self = .accessibility5
        default: return nil
        }
    }
}

extension CGSize {
    init?(fromSnapValue value: String) {
        let parts = value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0 else {
            return nil
        }
        self.init(width: width, height: height)
    }
}

extension UIColor {
    convenience init?(fromSnapHex value: String) {
        if value.lowercased() == "clear" {
            self.init(white: 1, alpha: 0)
            return
        }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let hex = Int(cleaned, radix: 16) else {
            return nil
        }
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

enum SnapshotWriter {
    static func write(image: UIImage, filename: String) throws {
        guard let data = image.pngData() else {
            throw SnapshotWriteError.encodingFailed
        }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SnapshotWriteError.documentsDirectoryMissing
        }
        let outputURL = documents.appendingPathComponent(filename)

        let tempURL = outputURL.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tempURL)
        try data.write(to: tempURL, options: .atomic)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: outputURL)
    }
}

enum SnapshotWriteError: Error, CustomStringConvertible {
    case encodingFailed
    case documentsDirectoryMissing

    var description: String {
        switch self {
        case .encodingFailed:
            return "PNG encoding failed."
        case .documentsDirectoryMissing:
            return "Documents directory unavailable."
        }
    }
}

struct SnapshotListCommand {
    private struct Payload: Encodable {
        struct ScenePayload: Encodable {
            struct Size: Encodable {
                let width: Double
                let height: Double
                let scale: Int
            }

            let id: String
            let size: Size?
            let summary: String?
        }

        let scenes: [ScenePayload]

        init(scenes: [SnapshotRegistry.Scene]) {
            self.scenes = scenes.map { scene in
                ScenePayload(
                    id: scene.id,
                    size: scene.size.map { size in
                        ScenePayload.Size(width: Double(size.width), height: Double(size.height), scale: size.scale)
                    },
                    summary: scene.summary
                )
            }
        }
    }

    static func run(config: RunnerConfig) -> Never {
        if SnapshotRegistry.allScenes().isEmpty {
            _ = SnapViewProvider.makeView(config: config)
        }
        let scenes = SnapshotRegistry.allScenes()
        let payload = Payload(scenes: scenes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(payload),
           let json = String(data: data, encoding: .utf8) {
            print("__SNAP_LIST__\(json)")
        } else {
            print("__SNAP_LIST__{\"scenes\":[]}")
        }
        RunnerExit.success()
    }
}

enum RunnerExit {
    static func success() -> Never {
        fflush(stdout)
        fflush(stderr)
        exit(EXIT_SUCCESS)
    }

    static func sceneMissing(_ id: String) -> Never {
        RunnerLogger.error("Scene '\(id)' not found in SnapshotRegistry.")
        fflush(stdout)
        fflush(stderr)
        exit(7)
    }

    static func fail(_ message: String) -> Never {
        RunnerLogger.error(message)
        fflush(stdout)
        fflush(stderr)
        exit(5)
    }
}

enum RunnerLogger {
    static func error(_ message: String) {
        fputs("[runner] \(message)\n", stderr)
    }
}
