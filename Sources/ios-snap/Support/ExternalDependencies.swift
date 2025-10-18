import Foundation

struct ExternalDependenciesConfig {
    let workspace: String?
    let project: String?
    let depSchemes: [String]
    let packageProducts: [PackageProductRequest]

    var hasAnyDependencies: Bool {
        !depSchemes.isEmpty || !packageProducts.isEmpty
    }

    var usesXcodeWorkspace: Bool {
        workspace != nil
    }

    var usesXcodeProject: Bool {
        project != nil
    }
}

struct PackageProductRequest {
    let packagePath: String
    let productName: String
    let schemeName: String
}

struct DependencyArtifacts {
    private(set) var frameworkSearchPaths: [String] = []
    private(set) var librarySearchPaths: [String] = []
    private(set) var swiftIncludePaths: [String] = []
    private(set) var otherLinkerFlags: [String] = []
    private(set) var frameworks: [URL] = []
    private(set) var dynamicLibraries: [URL] = []
    private(set) var resourceBundles: [URL] = []

    var isEmpty: Bool {
        frameworkSearchPaths.isEmpty &&
        librarySearchPaths.isEmpty &&
        swiftIncludePaths.isEmpty &&
        otherLinkerFlags.isEmpty &&
        frameworks.isEmpty &&
        dynamicLibraries.isEmpty &&
        resourceBundles.isEmpty
    }

    mutating func addFramework(at destination: URL, isDynamic: Bool) {
        appendUnique(&frameworkSearchPaths, value: destination.deletingLastPathComponent().path)
        let frameworkName = destination.deletingPathExtension().lastPathComponent
        appendUnique(&otherLinkerFlags, value: "-framework \(frameworkName)")
        if isDynamic {
            appendUniqueURL(&frameworks, value: destination)
        }
    }

    mutating func addLibrary(at destination: URL, isDynamic: Bool) {
        appendUnique(&librarySearchPaths, value: destination.deletingLastPathComponent().path)
        let baseName = destination.deletingPathExtension().lastPathComponent
        let trimmed = baseName.hasPrefix("lib") ? String(baseName.dropFirst(3)) : baseName
        appendUnique(&otherLinkerFlags, value: "-l\(trimmed)")
        if isDynamic {
            appendUniqueURL(&dynamicLibraries, value: destination)
        }
    }

    mutating func addSwiftModuleDirectory(at destination: URL) {
        appendUnique(&swiftIncludePaths, value: destination.deletingLastPathComponent().path)
    }

    mutating func addResourceBundle(at destination: URL) {
        appendUniqueURL(&resourceBundles, value: destination)
    }

    mutating func merge(_ other: DependencyArtifacts) {
        other.frameworkSearchPaths.forEach { appendUnique(&frameworkSearchPaths, value: $0) }
        other.librarySearchPaths.forEach { appendUnique(&librarySearchPaths, value: $0) }
        other.swiftIncludePaths.forEach { appendUnique(&swiftIncludePaths, value: $0) }
        other.otherLinkerFlags.forEach { appendUnique(&otherLinkerFlags, value: $0) }
        other.frameworks.forEach { appendUniqueURL(&frameworks, value: $0) }
        other.dynamicLibraries.forEach { appendUniqueURL(&dynamicLibraries, value: $0) }
        other.resourceBundles.forEach { appendUniqueURL(&resourceBundles, value: $0) }
    }

    func makeBuildOverrides() -> BuildSettingsOverrides? {
        guard !isEmpty else { return nil }
        return BuildSettingsOverrides(
            frameworkSearchPaths: frameworkSearchPaths,
            librarySearchPaths: librarySearchPaths,
            swiftIncludePaths: swiftIncludePaths,
            otherLinkerFlags: otherLinkerFlags
        )
    }

    var frameworkURLs: [URL] { frameworks }
    var dynamicLibraryURLs: [URL] { dynamicLibraries }
    var resourceBundleURLs: [URL] { resourceBundles }

    private func appendUnique(_ array: inout [String], value: String) {
        if !array.contains(value) {
            array.append(value)
        }
    }

    private func appendUniqueURL(_ array: inout [URL], value: URL) {
        if !array.contains(where: { $0.path == value.path }) {
            array.append(value)
        }
    }
}

struct BuildSettingsOverrides {
    var frameworkSearchPaths: [String] = []
    var librarySearchPaths: [String] = []
    var swiftIncludePaths: [String] = []
    var otherLinkerFlags: [String] = []

    var isEmpty: Bool {
        frameworkSearchPaths.isEmpty &&
        librarySearchPaths.isEmpty &&
        swiftIncludePaths.isEmpty &&
        otherLinkerFlags.isEmpty
    }

    func asXcconfigLines() -> [String] {
        var lines: [String] = []
        if !frameworkSearchPaths.isEmpty {
            lines.append("FRAMEWORK_SEARCH_PATHS = \(Self.joinValues(frameworkSearchPaths))")
        }
        if !librarySearchPaths.isEmpty {
            lines.append("LIBRARY_SEARCH_PATHS = \(Self.joinValues(librarySearchPaths))")
        }
        if !swiftIncludePaths.isEmpty {
            lines.append("SWIFT_INCLUDE_PATHS = \(Self.joinValues(swiftIncludePaths))")
        }
        if !otherLinkerFlags.isEmpty {
            let values = ["$(inherited)"] + otherLinkerFlags
            lines.append("OTHER_LDFLAGS = \(values.joined(separator: " "))")
        }
        return lines
    }

    private static func joinValues(_ paths: [String]) -> String {
        let quoted = paths.map { path -> String in
            if path.contains(" ") {
                return "\"\(path)\""
            }
            return path
        }
        return (["$(inherited)"] + quoted).joined(separator: " ")
    }
}
