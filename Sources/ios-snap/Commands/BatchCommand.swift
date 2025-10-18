import Foundation
import ArgumentParser
import Yams

struct Batch: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Render many scenes/variants from a YAML/JSON config."
    )

    @Option(name: .customLong("config"), help: "Path to YAML/JSON config file")
    var configPath: String

    @Flag(name: .customLong("continue-on-error"), help: "Continue processing remaining variants after a failure.")
    var continueOnError: Bool = false

    func run() throws {
        let loader = BatchConfigurationLoader()
        let configURL = try loader.resolveConfigURL(from: configPath)
        let configuration = try loader.loadConfiguration(from: configURL)
        let executor = BatchExecutor(
            configuration: configuration,
            configURL: configURL,
            continueOnError: continueOnError
        )
        try executor.execute()
    }
}

private struct BatchExecutor {
    let configuration: BatchConfiguration
    let configURL: URL
    let continueOnError: Bool

    func execute() throws {
        guard !configuration.scenes.isEmpty else {
            throw ValidationError("Batch config must contain at least one scene.")
        }

        let baseURL = configURL.deletingLastPathComponent()
        let globalDefaults = configuration.global?.makeSettings(relativeTo: baseURL) ?? VariantSettings()

        var successCount = 0
        var failureCount = 0
        var firstFailureExitCode: ExitCode?

        for scene in configuration.scenes {
            let scenePlan = try scene.makePlan(relativeTo: baseURL)

            IosSnapIO.printInfo("[batch] Scene '\(scenePlan.id)' — \(scene.variants.count) variants")
            if scene.variants.isEmpty {
                throw ValidationError("Scene '\(scenePlan.id)' must declare at least one variant.")
            }

            for (index, variant) in scene.variants.enumerated() {
                let variantIndex = index + 1
                let merged = globalDefaults.merging(variant.makeSettings(relativeTo: baseURL))
                let label = "\(scenePlan.id)#\(variantIndex)"

                guard let outPath = merged.outPath else {
                    throw ValidationError("Variant \(label) is missing required 'out' path.")
                }

                guard merged.device != nil || merged.udid != nil else {
                    throw ValidationError("Variant \(label) must specify either a device name or UDID.")
                }

                IosSnapIO.printInfo("[batch] Rendering \(label) → \(outPath)")

                let parameters = RenderParameters(
                    device: merged.device,
                    udid: merged.udid,
                    appearance: merged.appearance,
                    contentSize: merged.contentSize,
                    locale: merged.locale,
                    region: merged.region,
                    orientation: merged.orientation,
                    background: merged.background,
                    statusBar: merged.statusBar,
                    wait: merged.wait,
                    scale: merged.scale,
                    size: merged.size,
                    outPath: outPath,
                    expr: scenePlan.expr,
                    imports: scenePlan.importsString,
                    snippet: scenePlan.snippetPath,
                    scene: scenePlan.sceneIdentifier,
                    appScheme: merged.appScheme ?? scenePlan.appScheme,
                    workspace: merged.workspace ?? scenePlan.workspace,
                    project: merged.project ?? scenePlan.project,
                    depSchemes: merged.depSchemes ?? scenePlan.depSchemes ?? [],
                    packagePaths: merged.packages ?? scenePlan.packages ?? [],
                    packageProducts: merged.products ?? scenePlan.products ?? [],
                    dryRun: false,
                    bootDevice: false
                )
                let workflow = RenderWorkflow(parameters: parameters)

                do {
                    try workflow.performRender()
                    successCount += 1
                    IosSnapIO.printInfo("[batch] Completed \(label)")
                } catch let validation as ValidationError {
                    failureCount += 1
                    IosSnapIO.printError("[batch] \(label) failed: \(validation.message)")
                    if !continueOnError {
                        throw validation
                    }
                    firstFailureExitCode = firstFailureExitCode ?? ExitCode(1)
                } catch let exit as ExitCode {
                    failureCount += 1
                    IosSnapIO.printError("[batch] \(label) failed with exit code \(exit.rawValue).")
                    if !continueOnError {
                        throw exit
                    }
                    firstFailureExitCode = firstFailureExitCode ?? exit
                } catch {
                    failureCount += 1
                    IosSnapIO.printError("[batch] \(label) failed: \(error.localizedDescription)")
                    if !continueOnError {
                        throw error
                    }
                    firstFailureExitCode = firstFailureExitCode ?? ExitCode(1)
                }
            }
        }

        if failureCount > 0 {
            IosSnapIO.printError("[batch] Finished with \(failureCount) failure(s) out of \(successCount + failureCount) variant(s).")
            throw firstFailureExitCode ?? ExitCode(1)
        }

        IosSnapIO.printInfo("[batch] Finished \(successCount) variant(s) successfully.")
    }
}

private struct BatchConfiguration: Decodable {
    let global: VariantSpec?
    let scenes: [SceneSpec]

    struct SceneSpec: Decodable {
        let id: String
        private let rawImports: ImportField?
        let expr: String?
        let snippet: String?
        let sceneIdentifier: String?
        let variants: [VariantSpec]
        let project: String?
        let workspace: String?
        let appScheme: String?
        let depSchemes: [String]?
        let packages: [String]?
        let products: [String]?

        enum CodingKeys: String, CodingKey {
            case id
            case rawImports = "imports"
            case expr
            case snippet
            case sceneIdentifier = "scene"
            case variants
            case project
            case workspace
            case appScheme = "app_scheme"
            case depSchemes = "dep_schemes"
            case packages
            case products
        }

        func makePlan(relativeTo baseURL: URL) throws -> ScenePlan {
            let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty else {
                throw ValidationError("Scene id must not be empty.")
            }

            let imports = rawImports?.normalized ?? []
            let resolvedSnippet = resolvePath(snippet, relativeTo: baseURL)
            let resolvedProject = resolvePath(project, relativeTo: baseURL)
            let resolvedWorkspace = resolvePath(workspace, relativeTo: baseURL)
            let trimmedScene = sceneIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedExpr = expr?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedScheme = appScheme?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sanitizedDepSchemes = sanitizeDependencySchemes(depSchemes)
            let sanitizedPackages = sanitizePackagePaths(packages, relativeTo: baseURL)
            let sanitizedProducts = sanitizeRepeatableValues(products)

            if trimmedScene != nil {
                if trimmedExpr != nil {
                    throw ValidationError("Scene '\(normalizedID)' cannot specify both 'scene' and 'expr'.")
                }
            } else if resolvedSnippet == nil && (trimmedExpr == nil || trimmedExpr?.isEmpty == true) {
                throw ValidationError("Scene '\(normalizedID)' requires either 'expr' or 'snippet'.")
            }

            return ScenePlan(
                id: normalizedID,
                imports: imports,
                expr: trimmedExpr,
                snippetPath: resolvedSnippet,
                sceneIdentifier: trimmedScene,
                project: resolvedProject,
                workspace: resolvedWorkspace,
                appScheme: trimmedScheme,
                depSchemes: sanitizedDepSchemes,
                packages: sanitizedPackages,
                products: sanitizedProducts
            )
        }
    }
}

private struct ScenePlan {
    let id: String
    let imports: [String]
    let expr: String?
    let snippetPath: String?
    let sceneIdentifier: String?
    let project: String?
    let workspace: String?
    let appScheme: String?
    let depSchemes: [String]?
    let packages: [String]?
    let products: [String]?

    var importsString: String? {
        guard !imports.isEmpty else { return nil }
        return imports.joined(separator: ",")
    }
}

private struct VariantSpec: Decodable {
    let device: String?
    let udid: String?
    let appearance: String?
    let contentSize: String?
    let locale: String?
    let region: String?
    let orientation: String?
    let background: String?
    let statusBar: String?
    let wait: Double?
    let scale: Int?
    let size: String?
    let out: String?
    let project: String?
    let workspace: String?
    let appScheme: String?
    let depSchemes: [String]?
    let packages: [String]?
    let products: [String]?

    enum CodingKeys: String, CodingKey {
        case device
        case udid
        case appearance
        case contentSize = "content_size"
        case locale
        case region
        case orientation
        case background
        case statusBar = "status_bar"
        case wait
        case scale
        case size
        case out
        case project
        case workspace
        case appScheme = "app_scheme"
        case depSchemes = "dep_schemes"
        case packages
        case products
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = container.decodeTrimmedString(forKey: .device)
        udid = container.decodeTrimmedString(forKey: .udid)
        appearance = container.decodeTrimmedString(forKey: .appearance)
        contentSize = container.decodeTrimmedString(forKey: .contentSize)
        locale = container.decodeTrimmedString(forKey: .locale)
        region = container.decodeTrimmedString(forKey: .region)
        orientation = container.decodeTrimmedString(forKey: .orientation)
        background = container.decodeTrimmedString(forKey: .background)
        statusBar = container.decodeTrimmedString(forKey: .statusBar)
        wait = container.decodeFlexibleDouble(forKey: .wait)
        scale = container.decodeFlexibleInt(forKey: .scale)
        size = container.decodeTrimmedString(forKey: .size)
        out = container.decodeTrimmedString(forKey: .out)
        project = container.decodeTrimmedString(forKey: .project)
        workspace = container.decodeTrimmedString(forKey: .workspace)
        appScheme = container.decodeTrimmedString(forKey: .appScheme)
        depSchemes = try container.decodeIfPresent([String].self, forKey: .depSchemes)
        packages = try container.decodeIfPresent([String].self, forKey: .packages)
        products = try container.decodeIfPresent([String].self, forKey: .products)
    }

    func makeSettings(relativeTo baseURL: URL) -> VariantSettings {
        VariantSettings(
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
            outPath: resolvePath(out, relativeTo: baseURL),
            project: resolvePath(project, relativeTo: baseURL),
            workspace: resolvePath(workspace, relativeTo: baseURL),
            appScheme: appScheme?.trimmingCharacters(in: .whitespacesAndNewlines),
            depSchemes: sanitizeDependencySchemes(depSchemes),
            packages: sanitizePackagePaths(packages, relativeTo: baseURL),
            products: sanitizeRepeatableValues(products)
        )
    }
}

private struct VariantSettings {
    var device: String?
    var udid: String?
    var appearance: String?
    var contentSize: String?
    var locale: String?
    var region: String?
    var orientation: String?
    var background: String?
    var statusBar: String?
    var wait: Double?
    var scale: Int?
    var size: String?
    var outPath: String?
    var project: String?
    var workspace: String?
    var appScheme: String?
    var depSchemes: [String]?
    var packages: [String]?
    var products: [String]?

    func merging(_ override: VariantSettings) -> VariantSettings {
        VariantSettings(
            device: override.device ?? device,
            udid: override.udid ?? udid,
            appearance: override.appearance ?? appearance,
            contentSize: override.contentSize ?? contentSize,
            locale: override.locale ?? locale,
            region: override.region ?? region,
            orientation: override.orientation ?? orientation,
            background: override.background ?? background,
            statusBar: override.statusBar ?? statusBar,
            wait: override.wait ?? wait,
            scale: override.scale ?? scale,
            size: override.size ?? size,
            outPath: override.outPath ?? outPath,
            project: override.project ?? project,
            workspace: override.workspace ?? workspace,
            appScheme: override.appScheme ?? appScheme,
            depSchemes: override.depSchemes ?? depSchemes,
            packages: override.packages ?? packages,
            products: override.products ?? products
        )
    }
}

private struct BatchConfigurationLoader {
    func resolveConfigURL(from rawPath: String) throws -> URL {
        let expanded = CommandValidators.expandPath(rawPath)
        let url = URL(fileURLWithPath: expanded)
        if !FileManager.default.fileExists(atPath: url.path) {
            throw ValidationError("Config file not found at \(url.path).")
        }
        return url
    }

    func loadConfiguration(from url: URL) throws -> BatchConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ValidationError("Failed to read config file at \(url.path): \(error.localizedDescription)")
        }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "yaml", "yml":
            let decoder = YAMLDecoder()
            let string = String(decoding: data, as: UTF8.self)
            do {
                return try decoder.decode(BatchConfiguration.self, from: string)
            } catch {
                throw ValidationError("Failed to parse YAML: \(describeDecodingError(error))")
            }
        case "json":
            let decoder = JSONDecoder()
            do {
                return try decoder.decode(BatchConfiguration.self, from: data)
            } catch {
                throw ValidationError("Failed to parse JSON: \(describeDecodingError(error))")
            }
        default:
            throw ValidationError("Unsupported config format '\(ext)'. Expected .yml, .yaml, or .json.")
        }
    }
}

private enum ImportField: Decodable {
    case list([String])
    case single(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            self = .list(list)
            return
        }
        if let single = try? container.decode(String.self) {
            self = .single(single)
            return
        }
        throw DecodingError.typeMismatch(
            ImportField.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected string or string array for imports."
            )
        )
    }

    var normalized: [String] {
        switch self {
        case .list(let values):
            return ImportField.cleanup(values)
        case .single(let value):
            return ImportField.cleanup([value])
        }
    }

    private static func cleanup(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}

private func sanitizeDependencySchemes(_ values: [String]?) -> [String]? {
    guard let values else { return nil }
    var seen: Set<String> = []
    var result: [String] = []
    for raw in values {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if seen.insert(trimmed).inserted {
            result.append(trimmed)
        }
    }
    return result
}

private func sanitizeRepeatableValues(_ values: [String]?) -> [String]? {
    guard let values else { return nil }
    var result: [String] = []
    for raw in values {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        result.append(trimmed)
    }
    return result
}

private func sanitizePackagePaths(_ values: [String]?, relativeTo baseURL: URL) -> [String]? {
    guard let sanitized = sanitizeRepeatableValues(values) else { return nil }
    var resolved: [String] = []
    for path in sanitized {
        if let resolvedPath = resolvePath(path, relativeTo: baseURL) {
            resolved.append(resolvedPath)
        }
    }
    return resolved
}

private func resolvePath(_ rawPath: String?, relativeTo baseURL: URL) -> String? {
    guard let rawPath else { return nil }
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let expanded = CommandValidators.expandPath(trimmed)
    if expanded.hasPrefix("/") {
        return expanded
    }
    return baseURL.appendingPathComponent(expanded).path
}

private func describeDecodingError(_ error: Error) -> String {
    let primary = error.localizedDescription
    let verbose = String(describing: error)
    if verbose.isEmpty || verbose == primary {
        return primary
    }
    if verbose.contains(primary) {
        return verbose
    }
    return "\(primary) (\(verbose))"
}

private extension KeyedDecodingContainer where Key: CodingKey {
    func decodeTrimmedString(forKey key: Key) -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return String(doubleValue)
        }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
