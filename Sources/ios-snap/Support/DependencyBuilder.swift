import Foundation

struct DependencyBuilder {
    enum BuilderError: Error {
        case stagingDirectoryFailed(URL, Error)
        case derivedDataCleanupFailed(URL, Error)
        case buildFailed(target: String, message: String)
        case productsMissing(target: String)
        case copyFailed(source: URL, destination: URL, underlying: Error)
        case xcframeworkInfoMissing(URL)
        case xcframeworkMissingSlice(URL, SimulatorArchitecture)
        case xcframeworkUnsupportedProduct(URL, String)

        var description: String {
            switch self {
            case .stagingDirectoryFailed(let url, let error):
                return "Failed to prepare dependency staging directory at \(url.path): \(error.localizedDescription)"
            case .derivedDataCleanupFailed(let url, let error):
                return "Unable to reset derived data folder at \(url.path): \(error.localizedDescription)"
            case .buildFailed(let target, let message):
                return "Building dependency '\(target)' failed: \(message)"
            case .productsMissing(let target):
                return "No frameworks, libraries, or Swift modules produced by dependency '\(target)'."
            case .copyFailed(let source, let destination, let underlying):
                return "Failed to stage dependency artifact from \(source.path) to \(destination.path): \(underlying.localizedDescription)"
            case .xcframeworkInfoMissing(let url):
                return "Failed to parse Info.plist for XCFramework at \(url.path)."
            case .xcframeworkMissingSlice(let url, let architecture):
                return "XCFramework at \(url.path) does not contain an iOS simulator slice for \(architecture.rawValue)."
            case .xcframeworkUnsupportedProduct(let url, let product):
                return "XCFramework at \(url.path) contains unsupported product type '\(product)'."
            }
        }
    }

    private let simulatorArchitecture = SimulatorArchitecture.host

    func stageDependencies(config: ExternalDependenciesConfig, workspace: RunnerBuilder.Workspace) throws -> DependencyArtifacts {
        guard config.hasAnyDependencies else { return DependencyArtifacts() }

        let paths = try preparePaths(in: workspace)
        var aggregated = DependencyArtifacts()

        if !config.depSchemes.isEmpty {
            let schemeArtifacts = try stageSchemes(config: config, paths: paths)
            aggregated.merge(schemeArtifacts)
        }

        if !config.packageProducts.isEmpty {
            let packageArtifacts = try stagePackageProducts(config: config, paths: paths)
            aggregated.merge(packageArtifacts)
        }

        return aggregated
    }

    // MARK: - Paths

    private struct StagePaths {
        let frameworksStaging: URL
        let librariesStaging: URL
        let modulesStaging: URL
        let bundlesStaging: URL
        let derivedRoot: URL
    }

    private func preparePaths(in workspace: RunnerBuilder.Workspace) throws -> StagePaths {
        let dependenciesRoot = workspace.rootURL.appendingPathComponent("Dependencies", isDirectory: true)
        let stagingRoot = dependenciesRoot.appendingPathComponent("Staging", isDirectory: true)
        let frameworksStaging = stagingRoot.appendingPathComponent("Frameworks", isDirectory: true)
        let librariesStaging = stagingRoot.appendingPathComponent("Libraries", isDirectory: true)
        let modulesStaging = stagingRoot.appendingPathComponent("Modules", isDirectory: true)
        let bundlesStaging = stagingRoot.appendingPathComponent("Bundles", isDirectory: true)
        let derivedRoot = dependenciesRoot.appendingPathComponent("DerivedData", isDirectory: true)

        try recreateDirectory(frameworksStaging)
        try recreateDirectory(librariesStaging)
        try recreateDirectory(modulesStaging)
        try recreateDirectory(bundlesStaging)
        try ensureDirectoryExists(derivedRoot)

        return StagePaths(
            frameworksStaging: frameworksStaging,
            librariesStaging: librariesStaging,
            modulesStaging: modulesStaging,
            bundlesStaging: bundlesStaging,
            derivedRoot: derivedRoot
        )
    }

    // MARK: - Xcode Schemes

    private func stageSchemes(config: ExternalDependenciesConfig, paths: StagePaths) throws -> DependencyArtifacts {
        var aggregated = DependencyArtifacts()

        for scheme in config.depSchemes {
            IosSnapIO.printInfo("[deps] Building scheme '\(scheme)'")
            let artifacts = try buildScheme(
                scheme: scheme,
                config: config,
                paths: paths
            )
            aggregated.merge(artifacts)
        }

        return aggregated
    }

    private func buildScheme(
        scheme: String,
        config: ExternalDependenciesConfig,
        paths: StagePaths
    ) throws -> DependencyArtifacts {
        let sanitizedName = sanitize(label: scheme)
        let schemeDerivedData = paths.derivedRoot.appendingPathComponent("Scheme_\(sanitizedName)", isDirectory: true)

        do {
            try recreateDirectory(schemeDerivedData)
        } catch {
            throw BuilderError.derivedDataCleanupFailed(schemeDerivedData, error)
        }

        var command = ["xcodebuild"]
        if let workspacePath = config.workspace {
            command.append(contentsOf: ["-workspace", workspacePath])
        }
        if let projectPath = config.project {
            command.append(contentsOf: ["-project", projectPath])
        }
        command.append(contentsOf: [
            "-scheme", scheme,
            "-sdk", "iphonesimulator",
            "-configuration", "Release",
            "-derivedDataPath", schemeDerivedData.path,
            "build"
        ])
        command.append(contentsOf: architectureOverrides())

        try runXcodebuild(command, target: scheme)

        let productsURL = schemeDerivedData
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Release-iphonesimulator", isDirectory: true)

        return try collectArtifacts(
            label: scheme,
            productsURL: productsURL,
            paths: paths
        )
    }

    // MARK: - SwiftPM Packages

    private func stagePackageProducts(config: ExternalDependenciesConfig, paths: StagePaths) throws -> DependencyArtifacts {
        var aggregated = DependencyArtifacts()

        for request in config.packageProducts {
            IosSnapIO.printInfo("[deps] Building package product '\(request.productName)'")
            let artifacts = try buildPackageProduct(request: request, paths: paths)
            aggregated.merge(artifacts)
        }

        return aggregated
    }

    private func buildPackageProduct(
        request: PackageProductRequest,
        paths: StagePaths
    ) throws -> DependencyArtifacts {
        let sanitizedName = sanitize(label: request.productName)
        let packageDerivedData = paths.derivedRoot.appendingPathComponent("Package_\(sanitizedName)", isDirectory: true)

        do {
            try recreateDirectory(packageDerivedData)
        } catch {
            throw BuilderError.derivedDataCleanupFailed(packageDerivedData, error)
        }

        var command = [
            "xcodebuild",
            "-scheme", request.schemeName,
            "-target", request.productName,
            "-sdk", "iphonesimulator",
            "-destination", "generic/platform=iOS Simulator",
            "-configuration", "Release",
            "-derivedDataPath", packageDerivedData.path,
            "BUILD_LIBRARY_FOR_DISTRIBUTION=YES",
            "build"
        ]
        command.append(contentsOf: architectureOverrides())

        try runXcodebuild(command, target: request.productName, cwd: request.packagePath)

        let productsURL = packageDerivedData
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Release-iphonesimulator", isDirectory: true)

        return try collectArtifacts(
            label: request.productName,
            productsURL: productsURL,
            paths: paths
        )
    }

    // MARK: - Artifact Collection

    private func collectArtifacts(
        label: String,
        productsURL: URL,
        paths: StagePaths
    ) throws -> DependencyArtifacts {
        var artifacts = DependencyArtifacts()
        var stagedFrameworks = 0
        var stagedLibraries = 0
        var stagedModules = 0
        var stagedBundles = 0

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: productsURL.path) else {
            throw BuilderError.productsMissing(target: label)
        }

        let enumerator = fileManager.enumerator(
            at: productsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let pathExtension = fileURL.pathExtension.lowercased()
            if pathExtension == "xcframework" {
                enumerator?.skipDescendants()
                let xcResult = try stageXCFramework(at: fileURL, paths: paths)
                artifacts.merge(xcResult.artifacts)
                stagedFrameworks += xcResult.frameworks
                stagedLibraries += xcResult.libraries
                stagedModules += xcResult.modules
                stagedBundles += xcResult.bundles
                continue
            }
            switch pathExtension {
            case "framework":
                enumerator?.skipDescendants()
                let destination = paths.frameworksStaging.appendingPathComponent(fileURL.lastPathComponent)
                try replaceItemIfNeeded(at: destination)
                do {
                    try fileManager.copyItem(at: fileURL, to: destination)
                } catch {
                    throw BuilderError.copyFailed(source: fileURL, destination: destination, underlying: error)
                }
                let isDynamic = isDynamicFramework(at: destination)
                artifacts.addFramework(at: destination, isDynamic: isDynamic)
                stagedFrameworks += 1

            case "a", "dylib":
                let destination = paths.librariesStaging.appendingPathComponent(fileURL.lastPathComponent)
                try replaceItemIfNeeded(at: destination)
                do {
                    try fileManager.copyItem(at: fileURL, to: destination)
                } catch {
                    throw BuilderError.copyFailed(source: fileURL, destination: destination, underlying: error)
                }
                artifacts.addLibrary(at: destination, isDynamic: pathExtension == "dylib")
                stagedLibraries += 1

            case "swiftmodule":
                enumerator?.skipDescendants()
                let destination = paths.modulesStaging.appendingPathComponent(fileURL.lastPathComponent)
                try replaceItemIfNeeded(at: destination)
                do {
                    try fileManager.copyItem(at: fileURL, to: destination)
                } catch {
                    throw BuilderError.copyFailed(source: fileURL, destination: destination, underlying: error)
                }
                artifacts.addSwiftModuleDirectory(at: destination)
                stagedModules += 1

            case "bundle":
                enumerator?.skipDescendants()
                let destination = paths.bundlesStaging.appendingPathComponent(fileURL.lastPathComponent)
                try replaceItemIfNeeded(at: destination)
                do {
                    try fileManager.copyItem(at: fileURL, to: destination)
                } catch {
                    throw BuilderError.copyFailed(source: fileURL, destination: destination, underlying: error)
                }
                artifacts.addResourceBundle(at: destination)
                stagedBundles += 1

            default:
                continue
            }
        }

        if stagedFrameworks == 0 && stagedLibraries == 0 && stagedModules == 0 && stagedBundles == 0 {
            throw BuilderError.productsMissing(target: label)
        }

        var summary: [String] = []
        if stagedFrameworks > 0 {
            summary.append("\(stagedFrameworks) framework(s)")
        }
        if stagedLibraries > 0 {
            summary.append("\(stagedLibraries) library(s)")
        }
        if stagedModules > 0 {
            summary.append("\(stagedModules) module dir(s)")
        }
        if stagedBundles > 0 {
            summary.append("\(stagedBundles) bundle(s)")
        }
        IosSnapIO.printInfo("[deps] Staged \(summary.joined(separator: ", ")) for '\(label)'.")

        return artifacts
    }

    // MARK: - Helpers

    private func runXcodebuild(_ command: [String], target: String, cwd: String? = nil) throws {
        let buildResult: ShellResult
        do {
            buildResult = try Shell.run(command, env: ["NSUnbufferedIO": "YES"], cwd: cwd)
        } catch {
            throw BuilderError.buildFailed(target: target, message: "xcodebuild invocation failed.")
        }

        guard buildResult.status == 0 else {
            let stderr = buildResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = buildResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = [stderr, stdout].filter { !$0.isEmpty }.joined(separator: "\n")
            let message = combined.isEmpty ? "xcodebuild exited with status \(buildResult.status)." : combined
            throw BuilderError.buildFailed(target: target, message: message)
        }
    }

    private func sanitize(label: String) -> String {
        label
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func recreateDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw BuilderError.stagingDirectoryFailed(url, error)
            }
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw BuilderError.stagingDirectoryFailed(url, error)
        }
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw BuilderError.stagingDirectoryFailed(url, error)
            }
        }
    }

    private func replaceItemIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw BuilderError.stagingDirectoryFailed(url, error)
            }
        }
    }

    private func architectureOverrides() -> [String] {
        var overrides: [String] = [
            "ARCHS=\(simulatorArchitecture.rawValue)",
            "ONLY_ACTIVE_ARCH=YES",
            "SIMULATOR_ARCHS=\(simulatorArchitecture.rawValue)"
        ]
        if let excluded = simulatorArchitecture.excludedArchitecturesValue {
            overrides.append("EXCLUDED_ARCHS=\(excluded)")
        }
        return overrides
    }

    private func isDynamicFramework(at frameworkURL: URL) -> Bool {
        let binaryName = frameworkURL.deletingPathExtension().lastPathComponent
        let binaryURL = frameworkURL.appendingPathComponent(binaryName)
        guard let handle = try? FileHandle(forReadingFrom: binaryURL) else {
            return true
        }
        defer { try? handle.close() }
        let header: Data
        do {
            guard let data = try handle.read(upToCount: 8) else { return true }
            header = data
        } catch {
            return true
        }
        let archiveSignature = Data("!<arch>\n".utf8)
        if header.count >= archiveSignature.count && header.prefix(archiveSignature.count) == archiveSignature {
            return false
        }
        return true
    }

    private struct XCFrameworkInfo: Decodable {
        struct Library: Decodable {
            let libraryIdentifier: String
            let libraryPath: String
            let headersPath: String?
            let swiftModulePath: String?
            let resourcesPath: String?
            let supportedArchitectures: [String]
            let supportedPlatform: String
            let supportedPlatformVariant: String?

            private enum CodingKeys: String, CodingKey {
                case libraryIdentifier = "LibraryIdentifier"
                case libraryPath = "LibraryPath"
                case headersPath = "HeadersPath"
                case swiftModulePath = "SwiftModulePath"
                case resourcesPath = "ResourcesPath"
                case supportedArchitectures = "SupportedArchitectures"
                case supportedPlatform = "SupportedPlatform"
                case supportedPlatformVariant = "SupportedPlatformVariant"
            }

            var isIosSimulator: Bool {
                supportedPlatform.lowercased() == "ios" &&
                (supportedPlatformVariant?.lowercased() == "simulator")
            }
        }

        let availableLibraries: [Library]

        private enum CodingKeys: String, CodingKey {
            case availableLibraries = "AvailableLibraries"
        }
    }

    private struct StageResult {
        var artifacts: DependencyArtifacts
        var frameworks: Int
        var libraries: Int
        var modules: Int
        var bundles: Int
    }

    private func stageXCFramework(at url: URL, paths: StagePaths) throws -> StageResult {
        let infoPlistURL = url.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL) else {
            throw BuilderError.xcframeworkInfoMissing(url)
        }

        let decoder = PropertyListDecoder()
        let info: XCFrameworkInfo
        do {
            info = try decoder.decode(XCFrameworkInfo.self, from: data)
        } catch {
            throw BuilderError.xcframeworkInfoMissing(url)
        }

        let simulatorLibraries = info.availableLibraries.filter { $0.isIosSimulator }
        guard !simulatorLibraries.isEmpty else {
            throw BuilderError.xcframeworkMissingSlice(url, simulatorArchitecture)
        }

        let hostArchs = simulatorArchitecture.supportedArchitectures
        let selectedLibrary = simulatorLibraries.first { library in
            !hostArchs.isDisjoint(with: Set(library.supportedArchitectures))
        } ?? simulatorLibraries.first!

        let fileManager = FileManager.default
        var result = StageResult(artifacts: DependencyArtifacts(), frameworks: 0, libraries: 0, modules: 0, bundles: 0)

        let librarySource = url.appendingPathComponent(selectedLibrary.libraryPath)
        let lowercasedExtension = librarySource.pathExtension.lowercased()

        switch lowercasedExtension {
        case "framework":
            let destination = paths.frameworksStaging.appendingPathComponent(librarySource.lastPathComponent)
            try replaceItemIfNeeded(at: destination)
            do {
                try fileManager.copyItem(at: librarySource, to: destination)
            } catch {
                throw BuilderError.copyFailed(source: librarySource, destination: destination, underlying: error)
            }
            let isDynamic = isDynamicFramework(at: destination)
            result.artifacts.addFramework(at: destination, isDynamic: isDynamic)
            result.frameworks += 1
        case "a", "dylib":
            let destination = paths.librariesStaging.appendingPathComponent(librarySource.lastPathComponent)
            try replaceItemIfNeeded(at: destination)
            do {
                try fileManager.copyItem(at: librarySource, to: destination)
            } catch {
                throw BuilderError.copyFailed(source: librarySource, destination: destination, underlying: error)
            }
            result.artifacts.addLibrary(at: destination, isDynamic: lowercasedExtension == "dylib")
            result.libraries += 1
        default:
            throw BuilderError.xcframeworkUnsupportedProduct(url, selectedLibrary.libraryPath)
        }

        if let swiftModulePath = selectedLibrary.swiftModulePath {
            let moduleSource = url.appendingPathComponent(swiftModulePath)
            if fileManager.fileExists(atPath: moduleSource.path) {
                let destination = paths.modulesStaging.appendingPathComponent(moduleSource.lastPathComponent)
                try replaceItemIfNeeded(at: destination)
                do {
                    try fileManager.copyItem(at: moduleSource, to: destination)
                } catch {
                    throw BuilderError.copyFailed(source: moduleSource, destination: destination, underlying: error)
                }
                result.artifacts.addSwiftModuleDirectory(at: destination)
                result.modules += 1
            }
        }

        if let resourcesPath = selectedLibrary.resourcesPath {
            let resourcesSource = url.appendingPathComponent(resourcesPath)
            if fileManager.fileExists(atPath: resourcesSource.path) {
                let destination = paths.bundlesStaging.appendingPathComponent(resourcesSource.lastPathComponent)
                try replaceItemIfNeeded(at: destination)
                do {
                    try fileManager.copyItem(at: resourcesSource, to: destination)
                } catch {
                    throw BuilderError.copyFailed(source: resourcesSource, destination: destination, underlying: error)
                }
                result.artifacts.addResourceBundle(at: destination)
                result.bundles += 1
            }
        }

        return result
    }
}
