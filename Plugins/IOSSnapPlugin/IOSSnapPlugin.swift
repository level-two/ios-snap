import Foundation
import PackagePlugin

@main
struct IOSSnapPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool: PluginContext.Tool
        do {
            tool = try context.tool(named: "ios-snap")
        } catch {
            Diagnostics.error("Unable to locate ios-snap executable. Build the package to produce the binary.")
            throw error
        }

        try runTool(at: tool.path, arguments: arguments, workingDirectory: context.package.directory)
    }

    private func runTool(at toolPath: Path, arguments: [String], workingDirectory: Path) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath.string)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory.string)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            Diagnostics.error("Failed to start ios-snap: \(error.localizedDescription)")
            throw error
        }

        process.waitUntilExit()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            if process.terminationReason == .exit {
                throw PluginError.executionFailed(code: Int(process.terminationStatus))
            } else {
                throw PluginError.executionTerminated(signal: Int(process.terminationStatus))
            }
        }
    }
}

enum PluginError: Error {
    case executionFailed(code: Int)
    case executionTerminated(signal: Int)
}

extension PluginError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .executionFailed(let code):
            return "ios-snap exited with code \(code)."
        case .executionTerminated(let signal):
            return "ios-snap terminated by signal \(signal)."
        }
    }
}

extension PluginError: CustomStringConvertible {
    var description: String {
        switch self {
        case .executionFailed(let code):
            return "ios-snap exited with code \(code)."
        case .executionTerminated(let signal):
            return "ios-snap terminated by signal \(signal)."
        }
    }
}
