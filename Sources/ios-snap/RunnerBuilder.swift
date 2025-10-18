import Foundation

struct RunnerBuilder {
    enum SnippetInput {
        case expression(expr: String, imports: [String])
        case snippetFile(path: String, imports: [String])
    }

    struct Workspace {
        let rootURL: URL
        let isFallbackLocation: Bool

        var projectURL: URL {
            rootURL.appendingPathComponent("Runner.xcodeproj", isDirectory: true)
        }

        var projectPath: String {
            projectURL.path
        }

        var runnerSourcesURL: URL {
            rootURL.appendingPathComponent("Runner", isDirectory: true)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    enum BuilderError: Error, CustomStringConvertible {
        case templateDirectoryMissing(URL)
        case failedToCreateWorkspaceDirectory(URL, Error)
        case failedToCopyTemplate(source: URL, destination: URL, error: Error)
        case snippetFileNotFound(String)
        case snippetCopyFailed(source: URL, destination: URL, error: Error)
        case missingExpression
        case invalidImport(String)
        case rootViewNotFound(URL)
        case tokenNotFound(String)
        case writeFailed(URL, Error)

        var description: String {
            switch self {
            case .templateDirectoryMissing(let url):
                return "Runner template missing at \(url.path)."
            case .failedToCreateWorkspaceDirectory(let url, let error):
                return "Unable to create temporary workspace at \(url.path): \(error)."
            case .failedToCopyTemplate(let source, let destination, let error):
                return "Failed to copy template from \(source.path) to \(destination.path): \(error)."
            case .snippetFileNotFound(let path):
                return "Snippet file not found at \(path)."
            case .snippetCopyFailed(let source, let destination, let error):
                return "Failed to copy snippet file from \(source.path) to \(destination.path): \(error)."
            case .missingExpression:
                return "Inline expression is required when --expr is used."
            case .invalidImport(let module):
                return "Invalid module name '\(module)'. Modules must match [A-Za-z_][A-Za-z0-9_]* optionally separated by dots."
            case .rootViewNotFound(let url):
                return "RootView.swift not found at \(url.path)."
            case .tokenNotFound(let token):
                return "Token \(token) not found in template."
            case .writeFailed(let url, let error):
                return "Failed to write to \(url.path): \(error)."
            }
        }
    }

    func prepareWorkspace(input: SnippetInput) throws -> Workspace {
        let templateURL = RunnerBuilderPaths.templateRoot
        guard FileManager.default.fileExists(atPath: templateURL.path) else {
            throw BuilderError.templateDirectoryMissing(templateURL)
        }

        let (baseDirectory, usedFallback) = try RunnerBuilderPaths.workspaceBaseDirectory()
        let workspaceURL = RunnerBuilderPaths.makeUniqueWorkspaceRoot(in: baseDirectory)
        do {
            try FileManager.default.copyItem(at: templateURL, to: workspaceURL)
        } catch {
            throw BuilderError.failedToCopyTemplate(source: templateURL, destination: workspaceURL, error: error)
        }

        let workspace = Workspace(rootURL: workspaceURL, isFallbackLocation: usedFallback)

        do {
            try injectImports(for: input, into: workspace)
            try injectExpression(for: input, into: workspace)
            if case .snippetFile(let snippetPath, _) = input {
                try replaceSnippetFile(at: workspace, with: snippetPath)
            }
            return workspace
        } catch {
            workspace.cleanup()
            throw error
        }
    }

    private func injectImports(for input: SnippetInput, into workspace: Workspace) throws {
        let modules: [String]
        switch input {
        case .expression(_, let imports):
            modules = try sanitizeModules(imports)
        case .snippetFile(_, let imports):
            modules = try sanitizeModules(imports)
        }
        guard !modules.isEmpty else {
            try replaceImports(in: workspace, with: "")
            return
        }
        let lines = modules.map { "import \($0)" }
        let replacement = lines.joined(separator: "\n") + "\n"
        try replaceImports(in: workspace, with: replacement)
    }

    private func injectExpression(for input: SnippetInput, into workspace: Workspace) throws {
        let rendered: String
        switch input {
        case .expression(let expr, _):
            let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw BuilderError.missingExpression
            }
            rendered = renderExpression(trimmed)
        case .snippetFile:
            rendered = "        return AnyView(Runner.makeView())"
        }
        try replaceExpression(in: workspace, with: rendered)
    }

    private func replaceImports(in workspace: Workspace, with text: String) throws {
        let rootViewURL = workspace.runnerSourcesURL.appendingPathComponent("RootView.swift")
        guard FileManager.default.fileExists(atPath: rootViewURL.path) else {
            throw BuilderError.rootViewNotFound(rootViewURL)
        }
        do {
            var contents = try String(contentsOf: rootViewURL, encoding: .utf8)
            guard contents.contains("//__SNAP_IMPORTS__") else {
                throw BuilderError.tokenNotFound("//__SNAP_IMPORTS__")
            }
            contents = contents.replacingOccurrences(of: "//__SNAP_IMPORTS__", with: text)
            try contents.write(to: rootViewURL, atomically: true, encoding: .utf8)
        } catch let error as BuilderError {
            throw error
        } catch {
            throw BuilderError.writeFailed(rootViewURL, error)
        }
    }

    private func replaceExpression(in workspace: Workspace, with rendered: String) throws {
        let rootViewURL = workspace.runnerSourcesURL.appendingPathComponent("RootView.swift")
        guard FileManager.default.fileExists(atPath: rootViewURL.path) else {
            throw BuilderError.rootViewNotFound(rootViewURL)
        }
        do {
            var contents = try String(contentsOf: rootViewURL, encoding: .utf8)
            guard let startRange = contents.range(of: "//__SNAP_EXPR_START__") else {
                throw BuilderError.tokenNotFound("//__SNAP_EXPR_START__")
            }
            guard let endRange = contents.range(of: "//__SNAP_EXPR_END__") else {
                throw BuilderError.tokenNotFound("//__SNAP_EXPR_END__")
            }
            let range = startRange.upperBound..<endRange.lowerBound
            let replacement = "\n\(rendered)\n"
            contents.replaceSubrange(range, with: replacement)
            try contents.write(to: rootViewURL, atomically: true, encoding: .utf8)
        } catch let error as BuilderError {
            throw error
        } catch {
            throw BuilderError.writeFailed(rootViewURL, error)
        }
    }

    private func replaceSnippetFile(at workspace: Workspace, with snippetPath: String) throws {
        let path = (snippetPath as NSString).expandingTildeInPath
        let snippetURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: snippetURL.path) else {
            throw BuilderError.snippetFileNotFound(snippetPath)
        }
        let destinationURL = workspace.runnerSourcesURL.appendingPathComponent("Snippet.swift")
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: snippetURL, to: destinationURL)
        } catch {
            throw BuilderError.snippetCopyFailed(source: snippetURL, destination: destinationURL, error: error)
        }
    }

    private func sanitizeModules(_ modules: [String]) throws -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in modules {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard isValidModuleName(trimmed) else {
                throw BuilderError.invalidImport(trimmed)
            }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private func isValidModuleName(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        guard !parts.isEmpty else { return false }
        for part in parts {
            guard let first = part.first, first.isLetter || first == "_" else { return false }
            guard part.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return false }
        }
        return true
    }

    private func renderExpression(_ expression: String) -> String {
        if expression.contains("\n") {
            let lines = expression.split(separator: "\n", omittingEmptySubsequences: false)
            let indented = lines.map { "            \($0)" }.joined(separator: "\n")
            return """
        return AnyView(
\(indented)
        )
"""
        } else {
            return "        return AnyView(\(expression))"
        }
    }
}

private enum RunnerBuilderPaths {
    static let templateRoot: URL = {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent() // RunnerBuilder.swift
            .deletingLastPathComponent() // ios-snap
            .deletingLastPathComponent() // Sources
            .appendingPathComponent("Templates/Runner", isDirectory: true)
    }()

    static func workspaceBaseDirectory() throws -> (URL, Bool) {
        let fm = FileManager.default

        if let overridePath = ProcessInfo.processInfo.environment["IOS_SNAP_CACHE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            let expanded = (overridePath as NSString).expandingTildeInPath
            let overrideURL = URL(fileURLWithPath: expanded, isDirectory: true)
            let (overrideSuccess, overrideError) = createDirectoryIfPossible(at: overrideURL, fileManager: fm)
            if overrideSuccess {
                return (overrideURL, false)
            }
            let error = overrideError ?? NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM), userInfo: [
                NSLocalizedDescriptionKey: "Failed to create IOS_SNAP_CACHE_DIR at \(overrideURL.path)"
            ])
            throw RunnerBuilder.BuilderError.failedToCreateWorkspaceDirectory(overrideURL, error)
        }

        let cachesRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("ios-snap", isDirectory: true)

        let (cachesSuccess, cachesError) = createDirectoryIfPossible(at: cachesRoot, fileManager: fm)
        if cachesSuccess {
            return (cachesRoot, false)
        }

        let fallback = fm.temporaryDirectory
            .appendingPathComponent("ios-snap", isDirectory: true)
        let (fallbackSuccess, fallbackError) = createDirectoryIfPossible(at: fallback, fileManager: fm)
        if fallbackSuccess {
            return (fallback, true)
        }

        throw RunnerBuilder.BuilderError.failedToCreateWorkspaceDirectory(fallback, fallbackError ?? cachesError ?? NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM), userInfo: [
            NSLocalizedDescriptionKey: "Failed to create temporary directory at \(fallback.path)"
        ]))
    }

    static func makeUniqueWorkspaceRoot(in parent: URL) -> URL {
        var candidate: URL
        repeat {
            candidate = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func createDirectoryIfPossible(at url: URL, fileManager: FileManager) -> (Bool, Error?) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            return (true, nil)
        } catch {
            return (false, error)
        }
    }
}
