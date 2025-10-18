import Foundation
import ArgumentParser

struct Render: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a single scene (snippet or registry)."
    )

    // Common flags
    @Option(help: "Device name, e.g. 'iPhone 15 Pro'.") var device: String?
    @Option(help: "Simulator UDID.") var udid: String?
    @Option(help: "light|dark|auto") var appearance: String?
    @Option(name: .customLong("content-size"), help: "Dynamic Type size: XS|S|M|L|XL|XXL|AX1..AX5") var contentSize: String?
    @Option(help: "Locale, e.g., pl-PL") var locale: String?
    @Option(help: "Region override") var region: String?
    @Option(help: "portrait|landscape") var orientation: String?
    @Option(help: "Background color (#RRGGBB) or 'clear'") var background: String?
    @Option(name: .customLong("status-bar"), help: "Status bar override string") var statusBar: String?
    @Option(help: "Delay before capture in seconds") var wait: Double?
    @Option(help: "Output scale: 2 or 3") var scale: Int?
    @Option(name: .customLong("out"), help: "Output file path (.png)") var outPath: String?
    @Option(help: "Absolute size in points, e.g., 393x852") var size: String?

    // Snippet-mode
    @Option(name: .customLong("expr"), help: "SwiftUI expression to render") var expr: String?
    @Option(name: .customLong("imports"), help: "Comma-separated modules to import") var imports: String?
    @Option(name: .customLong("snippet"), help: "Path to a Swift file with makeView() -> some View") var snippet: String?

    // Registry-mode
    @Option(name: .customLong("scene"), help: "Registry scene id, e.g., locks/default") var scene: String?
    @Option(name: .customLong("app-scheme"), help: "Xcode scheme for registry builds") var appScheme: String?
    @Option(name: .customLong("workspace"), help: "Path to .xcworkspace") var workspace: String?
    @Option(name: .customLong("project"), help: "Path to .xcodeproj") var project: String?
    @Option(name: .customLong("dep-scheme"), help: "Dependency scheme to prebuild before rendering (repeatable).") var depSchemes: [String] = []
    @Option(name: .customLong("package"), help: "Path to a SwiftPM package root for dependency builds (repeatable).") var packagePaths: [String] = []
    @Option(name: .customLong("product"), help: "SwiftPM product name to build (repeatable).") var packageProducts: [String] = []
    @Flag(name: .customLong("dry-run"), help: "Resolve simulator and validate inputs without rendering.") var dryRun: Bool = false
    @Flag(name: .customLong("boot"), help: "Boot the resolved simulator during dry-run.") var bootDevice: Bool = false

    func run() throws {
        let parameters = RenderParameters(
            device: device,
            udid: udid,
            appearance: appearance,
            contentSize: contentSize,
            locale: locale,
            region: region,
            orientation: orientation,
            background: background,
            statusBar: statusBar,
            wait: wait,
            scale: scale,
            size: size,
            outPath: outPath,
            expr: expr,
            imports: imports,
            snippet: snippet,
            scene: scene,
            appScheme: appScheme,
            workspace: workspace,
            project: project,
            depSchemes: depSchemes,
            packagePaths: packagePaths,
            packageProducts: packageProducts,
            dryRun: dryRun,
            bootDevice: bootDevice
        )

        let workflow = RenderWorkflow(parameters: parameters)
        if dryRun {
            try workflow.performDryRun()
        } else {
            try workflow.performRender()
        }
    }
}
