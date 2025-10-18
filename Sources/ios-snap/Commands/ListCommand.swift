import Foundation
import ArgumentParser

struct List: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available registry scenes (registry mode)."
    )

    @Option(help: "Device name, e.g. 'iPhone 15 Pro'.")
    var device: String?

    @Option(help: "Simulator UDID.")
    var udid: String?

    @Option(name: .customLong("imports"), help: "Comma-separated modules to import for registry bootstrap.")
    var imports: String?

    @Option(name: .customLong("snippet"), help: "Path to a Swift file that registers scenes.")
    var snippet: String?

    func run() throws {
        let snippetInput = try makeSnippetInput()
        let builder = RunnerBuilder()
        let workspace: RunnerBuilder.Workspace
        do {
            workspace = try builder.prepareWorkspace(input: snippetInput)
        } catch let error as RunnerBuilder.BuilderError {
            IosSnapIO.printError("[build] \(error.description)")
            throw ExitCode(2)
        }

        var shouldCleanupWorkspace = false
        defer {
            if shouldCleanupWorkspace {
                workspace.cleanup()
            } else {
                IosSnapIO.printInfo("[build] Preserving runner workspace at \(workspace.rootURL.path)")
            }
        }

        let locationNote = workspace.isFallbackLocation ? " (fallback)" : ""
        IosSnapIO.printInfo("[build] Prepared runner workspace\(locationNote): \(workspace.rootURL.path)")

        let manager = SimulatorManager()
        let resolved: SimulatorManager.ResolvedDevice
        do {
            resolved = try manager.resolveDevice(udid: udid, deviceName: device)
            IosSnapIO.printInfo("[sim] Using \(resolved.name) — \(resolved.udid) (\(resolved.runtime.displayName))")
        } catch let error as SimulatorManager.ManagerError {
            IosSnapIO.printError(describeSimulatorError(error))
            if case .missingDeviceArguments = error {
                throw ExitCode(1)
            }
            throw ExitCode(3)
        }

        do {
            try manager.bootIfNeeded(udid: resolved.udid)
            IosSnapIO.printInfo("[sim] Booted \(resolved.name)")
        } catch let error as SimulatorManager.ManagerError {
            IosSnapIO.printError(describeSimulatorError(error))
            throw ExitCode(3)
        }

        let pipeline = RunnerPipeline(
            workspace: workspace,
            device: resolved,
            buildOverrides: nil,
            dependencyArtifacts: nil
        )
        let launchResult: ShellResult
        do {
            let appURL = try pipeline.buildRunner()
            try pipeline.installRunner(appURL: appURL)
            launchResult = try pipeline.launchRunner(
                environment: [
                    "SNAP_COMMAND": "list",
                    "SNAP_OUT_FILENAME": "__snap_list__.json"
                ],
                arguments: []
            )
        } catch let pipelineError as RunnerPipeline.PipelineError {
            throw pipelineError.exitCode
        }

        guard let payloadLine = extractScenePayload(from: launchResult) else {
            IosSnapIO.printError("[run] Runner did not emit scene list payload.")
            throw ExitCode(5)
        }

        let decoded = try decodeScenes(from: payloadLine)
        if decoded.scenes.isEmpty {
            IosSnapIO.printInfo("No registry scenes registered.")
        } else {
            IosSnapIO.printInfo("Registered scenes:")
            for scene in decoded.scenes {
                var line = "- \(scene.id)"
                if let size = scene.size {
                    let width = Int(size.width.rounded())
                    let height = Int(size.height.rounded())
                    line += " (\(width)x\(height) @\(size.scale)x)"
                }
                if let summary = scene.summary, !summary.isEmpty {
                    line += " — \(summary)"
                }
                IosSnapIO.printInfo(line)
            }
        }
        shouldCleanupWorkspace = true
    }

    private func makeSnippetInput() throws -> RunnerBuilder.SnippetInput {
        if let snippet {
            return .snippetFile(path: snippet, imports: CommandValidators.parseImports(imports))
        }
        return .expression(expr: "EmptyView()", imports: CommandValidators.parseImports(imports))
    }

    private func extractScenePayload(from result: ShellResult) -> String? {
        let marker = "__SNAP_LIST__"
        let candidates = (result.stdout + "\n" + result.stderr)
            .split(separator: "\n")
            .map(String.init)
        if let line = candidates.first(where: { $0.contains(marker) }) {
            return line.replacingOccurrences(of: marker, with: "")
        }
        return nil
    }

    private func decodeScenes(from payload: String) throws -> SceneListPayload {
        let data = Data(payload.utf8)
        do {
            return try JSONDecoder().decode(SceneListPayload.self, from: data)
        } catch {
            IosSnapIO.printError("[run] Failed to decode scene list payload: \(error.localizedDescription)")
            throw ExitCode(5)
        }
    }

    private struct SceneListPayload: Decodable {
        struct Scene: Decodable {
            struct Size: Decodable {
                let width: Double
                let height: Double
                let scale: Int
            }

            let id: String
            let size: Size?
            let summary: String?
        }

        let scenes: [Scene]
    }
}
