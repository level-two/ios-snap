import Foundation
import ArgumentParser

struct RenderParameters {
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
    var expr: String?
    var imports: String?
    var snippet: String?
    var scene: String?
    var appScheme: String?
    var workspace: String?
    var project: String?
    var depSchemes: [String] = []
    var packagePaths: [String] = []
    var packageProducts: [String] = []
    var dryRun: Bool = false
    var bootDevice: Bool = false
}

enum RenderSnippetContext {
    case dryRun
    case render
}

struct RenderParameterParser {
    let parameters: RenderParameters

    func sceneIdentifier() throws -> String? {
        guard let raw = parameters.scene else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("--scene value cannot be empty.")
        }
        return trimmed
    }

    func snippetInput(context: RenderSnippetContext) throws -> RunnerBuilder.SnippetInput {
        let modules = CommandValidators.parseImports(parameters.imports)

        if parameters.snippet != nil && parameters.expr != nil {
            throw ValidationError("Provide either --expr or --snippet, not both.")
        }

        if let snippetPath = parameters.snippet {
            return .snippetFile(path: snippetPath, imports: modules)
        }

        if let expr = parameters.expr {
            let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError("Inline expression is required when --expr is used.")
            }
            return .expression(expr: trimmed, imports: modules)
        }

        if parameters.scene != nil {
            return .expression(expr: "EmptyView()", imports: modules)
        }

        switch context {
        case .dryRun:
            throw ValidationError("Snippet mode dry-run requires --expr '<SwiftUI expression>' or --snippet <file.swift>.")
        case .render:
            throw ValidationError("Snippet mode render requires --expr '<SwiftUI expression>' or --snippet <file.swift>.")
        }
    }

    func outputURL() throws -> URL {
        guard let outPath = parameters.outPath else {
            throw ValidationError("--out <path.png> is required.")
        }
        let expanded = CommandValidators.expandPath(outPath)
        guard expanded.lowercased().hasSuffix(".png") else {
            throw ValidationError("--out must point to a .png file.")
        }
        return URL(fileURLWithPath: expanded)
    }

    func externalDependencies() throws -> ExternalDependenciesConfig? {
        let sanitizedSchemes = try sanitizeSchemes(parameters.depSchemes)
        let sanitizedPackagePaths = try sanitizeRepeatableList(parameters.packagePaths, flag: "--package")
        let sanitizedPackageProducts = try sanitizeRepeatableList(parameters.packageProducts, flag: "--product")

        let workspacePath = try normalizeXcodePath(
            parameters.workspace,
            expectedExtension: "xcworkspace",
            flag: "--workspace"
        )
        let projectPath = try normalizeXcodePath(
            parameters.project,
            expectedExtension: "xcodeproj",
            flag: "--project"
        )

        if workspacePath != nil && projectPath != nil {
            throw ValidationError("Provide either --workspace or --project, not both.")
        }

        if sanitizedPackagePaths.count != sanitizedPackageProducts.count {
            throw ValidationError("Provide the same number of --package and --product options.")
        }

        if !sanitizedSchemes.isEmpty && workspacePath == nil && projectPath == nil {
            throw ValidationError("--dep-scheme requires --workspace or --project.")
        }

        let packageRequests = try makePackageRequests(
            paths: sanitizedPackagePaths,
            products: sanitizedPackageProducts
        )

        let hasWorkspaceOrProject = workspacePath != nil || projectPath != nil
        let hasAnyDependency = !sanitizedSchemes.isEmpty || !packageRequests.isEmpty

        if hasWorkspaceOrProject && !hasAnyDependency && parameters.scene == nil {
            throw ValidationError("When using --workspace/--project in snippet mode, add at least one --dep-scheme or --package/--product combination.")
        }

        if !hasWorkspaceOrProject && sanitizedSchemes.isEmpty && packageRequests.isEmpty {
            return nil
        }

        return ExternalDependenciesConfig(
            workspace: workspacePath,
            project: projectPath,
            depSchemes: sanitizedSchemes,
            packageProducts: packageRequests
        )
    }

    private func sanitizeSchemes(_ values: [String]) throws -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError("--dep-scheme cannot be empty.")
            }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private func sanitizeRepeatableList(_ values: [String], flag: String) throws -> [String] {
        var result: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError("\(flag) cannot be empty.")
            }
            result.append(trimmed)
        }
        return result
    }

    private func normalizeXcodePath(_ rawPath: String?, expectedExtension: String, flag: String) throws -> String? {
        guard let rawPath else { return nil }
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("\(flag) cannot be empty.")
        }
        let absolute = makeAbsolutePath(trimmed)
        let url = URL(fileURLWithPath: absolute)
        guard url.pathExtension.lowercased() == expectedExtension else {
            throw ValidationError("\(flag) must point to a .\(expectedExtension) bundle.")
        }
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: absolute, isDirectory: &isDirectory) || !isDirectory.boolValue {
            throw ValidationError("No file system entry found for \(flag) at \(absolute).")
        }
        return absolute
    }

    private func makePackageRequests(paths: [String], products: [String]) throws -> [PackageProductRequest] {
        guard !paths.isEmpty else { return [] }
        var result: [PackageProductRequest] = []
        let fm = FileManager.default
        for (path, product) in zip(paths, products) {
            let absolute = makeAbsolutePath(path)
            var isDirectory: ObjCBool = false
            if !fm.fileExists(atPath: absolute, isDirectory: &isDirectory) || !isDirectory.boolValue {
                throw ValidationError("SwiftPM package not found at \(absolute).")
            }
            let schemeName = detectPackageSchemeName(at: absolute) ?? URL(fileURLWithPath: absolute).lastPathComponent
            result.append(PackageProductRequest(packagePath: absolute, productName: product, schemeName: schemeName))
        }
        return result
    }

    private func detectPackageSchemeName(at packagePath: String) -> String? {
        let command = ["swift", "package", "describe", "--type", "json"]
        guard let result = try? Shell.run(command, cwd: packagePath), result.status == 0 else {
            return nil
        }

        guard let data = result.stdout.data(using: .utf8) else { return nil }
        struct PackageDescription: Decodable { let name: String }
        guard let description = try? JSONDecoder().decode(PackageDescription.self, from: data) else {
            return nil
        }
        let trimmed = description.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeAbsolutePath(_ path: String) -> String {
        let expanded = CommandValidators.expandPath(path)
        if expanded.hasPrefix("/") {
            return expanded
        }
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: cwd).appendingPathComponent(expanded).path
    }
}
