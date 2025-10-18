import Foundation
import Dispatch

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum ShellError: Error {
    case launchFailed
}

enum Shell {
    @discardableResult
    static func run(_ command: [String], env: [String: String] = [:], cwd: String? = nil) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        var envMerged = ProcessInfo.processInfo.environment
        env.forEach { envMerged[$0.key] = $0.value }
        process.environment = envMerged
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        let outPipe = Pipe(); process.standardOutput = outPipe
        let errPipe = Pipe(); process.standardError = errPipe

        do { try process.run() } catch { throw ShellError.launchFailed }

        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        }

        process.waitUntilExit()
        group.wait()

        return ShellResult(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
