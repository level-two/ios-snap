import Foundation
import ArgumentParser

struct RunnerPipeline {
    enum PipelineError: Swift.Error {
        case buildFailed(message: String)
        case installFailed(message: String)
        case launchFailed(message: String)
        case containerFailed(message: String)
        case outputMissing(message: String)
        case copyFailed(message: String)

        var exitCode: ExitCode {
            switch self {
            case .buildFailed:
                return ExitCode(2)
            case .installFailed:
                return ExitCode(3)
            case .launchFailed:
                return ExitCode(4)
            case .containerFailed, .outputMissing, .copyFailed:
                return ExitCode(6)
            }
        }
    }

    let workspace: RunnerBuilder.Workspace
    let device: SimulatorManager.ResolvedDevice
    let buildOverrides: BuildSettingsOverrides?
    let dependencyArtifacts: DependencyArtifacts?
    private let simulatorArchitecture = SimulatorArchitecture.host

    private var derivedDataURL: URL {
        workspace.rootURL.appendingPathComponent("DerivedData", isDirectory: true)
    }

    func buildRunner() throws -> URL {
        var buildCommand = [
            "xcodebuild",
            "-project", workspace.projectPath,
            "-scheme", "Runner",
            "-configuration", "Release",
            "-sdk", "iphonesimulator",
            "-destination", "id=\(device.udid)",
            "-derivedDataPath", derivedDataURL.path,
            "build"
        ]

        var xcconfigLines: [String] = []
        if let overrideLines = buildOverrides?.asXcconfigLines(), !overrideLines.isEmpty {
            xcconfigLines.append(contentsOf: overrideLines)
            IosSnapIO.printInfo("[deps] Applied dependency build settings overrides.")
        }
        xcconfigLines.append("ARCHS = \(simulatorArchitecture.rawValue)")
        xcconfigLines.append("ONLY_ACTIVE_ARCH = YES")
        if let excluded = simulatorArchitecture.excludedArchitecturesValue {
            xcconfigLines.append("EXCLUDED_ARCHS = \(excluded)")
        }
        xcconfigLines.append("SIMULATOR_ARCHS = \(simulatorArchitecture.rawValue)")

        if !xcconfigLines.isEmpty {
            let fileURL = workspace.rootURL.appendingPathComponent("Overrides.xcconfig")
            let contents = xcconfigLines.joined(separator: "\n") + "\n"
            do {
                try contents.write(to: fileURL, atomically: true, encoding: .utf8)
                buildCommand.insert(contentsOf: ["-xcconfig", fileURL.path], at: buildCommand.count - 1)
            } catch {
                IosSnapIO.printError("[deps] Failed to write overrides xcconfig: \(error.localizedDescription)")
            }
        }

        if ProcessInfo.processInfo.environment["IOS_SNAP_DEBUG_DEPS"] != nil {
            IosSnapIO.printInfo("[deps] xcodebuild command: \(buildCommand.joined(separator: " "))")
        }

        let buildResult: ShellResult
        do {
            buildResult = try Shell.run(buildCommand, env: ["NSUnbufferedIO": "YES"], cwd: workspace.rootURL.path)
        } catch {
            IosSnapIO.printError("[build] Failed to launch xcodebuild.")
            throw PipelineError.buildFailed(message: "xcodebuild invocation failed.")
        }

        guard buildResult.status == 0 else {
            let stderr = buildResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                IosSnapIO.printError("[build] \(stderr)")
            } else {
                IosSnapIO.printError("[build] xcodebuild failed with status \(buildResult.status).")
            }
            throw PipelineError.buildFailed(message: "xcodebuild exited with status \(buildResult.status).")
        }

        IosSnapIO.printInfo("[build] xcodebuild completed")

        let appURL = derivedDataURL
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Release-iphonesimulator", isDirectory: true)
            .appendingPathComponent("Runner.app", isDirectory: true)

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            IosSnapIO.printError("[build] Runner.app not found at \(appURL.path)")
            throw PipelineError.buildFailed(message: "Runner.app missing from build products.")
        }

        try embedRuntimeDependencies(into: appURL)

        return appURL
    }

    func installRunner(appURL: URL) throws {
        let installCommand = ["xcrun", "simctl", "install", device.udid, appURL.path]
        let installResult: ShellResult
        do {
            installResult = try Shell.run(installCommand)
        } catch {
            IosSnapIO.printError("[sim] Failed to launch simctl install.")
            throw PipelineError.installFailed(message: "simctl install invocation failed.")
        }

        guard installResult.status == 0 else {
            let stderr = installResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                IosSnapIO.printError("[sim] \(stderr)")
            } else {
                IosSnapIO.printError("[sim] simctl install failed with status \(installResult.status).")
            }
            throw PipelineError.installFailed(message: "simctl install exited with status \(installResult.status).")
        }

        IosSnapIO.printInfo("[sim] Installed Runner.app")
    }

    func launchRunner(environment: [String: String], arguments: [String]) throws -> ShellResult {
        var launchCommand: [String] = [
            "xcrun", "simctl", "launch",
            "--terminate-running-process",
            "--console",
            device.udid,
            "com.example.Runner"
        ]

        if !arguments.isEmpty {
            launchCommand.append("--args")
            launchCommand.append(contentsOf: arguments)
        }

        var launchEnvironment: [String: String] = [:]
        for (key, value) in environment {
            launchEnvironment["SIMCTL_CHILD_\(key)"] = value
        }

        let launchResult: ShellResult
        do {
            launchResult = try Shell.run(launchCommand, env: launchEnvironment)
        } catch {
            IosSnapIO.printError("[run] Failed to launch runner application.")
            throw PipelineError.launchFailed(message: "simctl launch invocation failed.")
        }

        guard launchResult.status == 0 else {
            let stderr = launchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                IosSnapIO.printError("[run] \(stderr)")
            } else {
                IosSnapIO.printError("[run] Runner exited with status \(launchResult.status).")
            }
            throw PipelineError.launchFailed(message: "Runner exited with status \(launchResult.status).")
        }

        return launchResult
    }

    func copyOutput(filename: String, to outputURL: URL) throws {
        let containerURL = try fetchAppContainer()
        let sourceURL = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            IosSnapIO.printError("[pull] Snapshot not found at \(sourceURL.path)")
            throw PipelineError.outputMissing(message: "Snapshot missing in runner container.")
        }

        let fm = FileManager.default
        let destinationDirectory = outputURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: destinationDirectory.path) {
            try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let tempURL = outputURL.appendingPathExtension("tmp")
        try? fm.removeItem(at: tempURL)
        do {
            try fm.copyItem(at: sourceURL, to: tempURL)
        } catch {
            IosSnapIO.printError("[pull] Failed to copy snapshot: \(error.localizedDescription)")
            throw PipelineError.copyFailed(message: "Failed to copy snapshot from runner container.")
        }

        do {
            if fm.fileExists(atPath: outputURL.path) {
                try fm.removeItem(at: outputURL)
            }
            try fm.moveItem(at: tempURL, to: outputURL)
        } catch {
            IosSnapIO.printError("[pull] Failed to move snapshot into place: \(error.localizedDescription)")
            throw PipelineError.copyFailed(message: "Failed to atomically move snapshot into destination.")
        }

        IosSnapIO.printInfo("[pull] Snapshot saved to \(outputURL.path)")
    }

    private func fetchAppContainer() throws -> URL {
        let command = [
            "xcrun", "simctl", "get_app_container",
            device.udid,
            "com.example.Runner",
            "data"
        ]

        let result: ShellResult
        do {
            result = try Shell.run(command)
        } catch {
            IosSnapIO.printError("[pull] Failed to locate app container.")
            throw PipelineError.containerFailed(message: "simctl get_app_container invocation failed.")
        }

        guard result.status == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                IosSnapIO.printError("[pull] \(stderr)")
            } else {
                IosSnapIO.printError("[pull] simctl get_app_container failed with status \(result.status).")
            }
            throw PipelineError.containerFailed(message: "simctl get_app_container exited with status \(result.status).")
        }

        let containerPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !containerPath.isEmpty else {
            IosSnapIO.printError("[pull] App container path is empty.")
            throw PipelineError.containerFailed(message: "App container path is empty.")
        }

        return URL(fileURLWithPath: containerPath, isDirectory: true)
    }

    private func embedRuntimeDependencies(into appURL: URL) throws {
        guard let artifacts = dependencyArtifacts else { return }
        let fileManager = FileManager.default

        let frameworksCount = artifacts.frameworkURLs.count
        let dylibCount = artifacts.dynamicLibraryURLs.count
        if frameworksCount > 0 || dylibCount > 0 {
            let frameworksDestination = appURL.appendingPathComponent("Frameworks", isDirectory: true)
            if !fileManager.fileExists(atPath: frameworksDestination.path) {
                do {
                    try fileManager.createDirectory(at: frameworksDestination, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    throw PipelineError.copyFailed(message: "Failed to prepare Runner.app Frameworks directory: \(error.localizedDescription)")
                }
            }

            for framework in artifacts.frameworkURLs {
                let destination = frameworksDestination.appendingPathComponent(framework.lastPathComponent, isDirectory: true)
                do {
                    try replaceItemIfNeeded(at: destination, fileManager: fileManager)
                    try fileManager.copyItem(at: framework, to: destination)
                } catch {
                    throw PipelineError.copyFailed(message: "Failed to embed framework \(framework.lastPathComponent): \(error.localizedDescription)")
                }
            }

            for dylib in artifacts.dynamicLibraryURLs {
                let destination = frameworksDestination.appendingPathComponent(dylib.lastPathComponent, isDirectory: false)
                do {
                    try replaceItemIfNeeded(at: destination, fileManager: fileManager)
                    try fileManager.copyItem(at: dylib, to: destination)
                } catch {
                    throw PipelineError.copyFailed(message: "Failed to embed dynamic library \(dylib.lastPathComponent): \(error.localizedDescription)")
                }
            }

            IosSnapIO.printInfo("[deps] Embedded \(frameworksCount) framework(s) and \(dylibCount) dylib(s) into Runner.app")
        }

        let bundleCount = artifacts.resourceBundleURLs.count
        if bundleCount > 0 {
            for bundle in artifacts.resourceBundleURLs {
                let destination = appURL.appendingPathComponent(bundle.lastPathComponent, isDirectory: true)
                do {
                    try replaceItemIfNeeded(at: destination, fileManager: fileManager)
                    try fileManager.copyItem(at: bundle, to: destination)
                } catch {
                    throw PipelineError.copyFailed(message: "Failed to copy resource bundle \(bundle.lastPathComponent): \(error.localizedDescription)")
                }
            }
            IosSnapIO.printInfo("[deps] Copied \(bundleCount) resource bundle(s) into Runner.app")
        }
    }

    private func replaceItemIfNeeded(at url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw PipelineError.copyFailed(message: "Failed to replace existing item at \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
