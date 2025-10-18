import Foundation
import ArgumentParser

@main
struct IosSnap: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ios-snap",
        abstract: "SwiftUI CLI snapshotter for iOS Simulator",
        version: "0.1.0",
        subcommands: [
            Devices.self,
            Render.self,
            Batch.self,
            List.self
        ],
        defaultSubcommand: nil
    )

    @Flag(name: .shortAndLong, help: "Enable verbose logging.")
    var verbose: Bool = false

    func run() throws {
        // Root command is a container; subcommands perform actions.
    }
}
