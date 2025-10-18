import Foundation
import ArgumentParser

struct Devices: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List available iOS simulators."
    )

    func run() throws {
        let command = ["xcrun", "simctl", "list", "--json", "devices"]
        let result = try Shell.run(command)

        guard result.status == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                IosSnapIO.printError(stderr)
            }
            throw ExitCode(result.status)
        }

        let payload: SimctlDeviceList
        do {
            payload = try Self.decodeDeviceList(from: result.stdout)
        } catch {
            IosSnapIO.printError("Failed to decode simulator list: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        var entries: [DeviceEntry] = []
        for (runtimeID, devices) in payload.devices {
            guard let runtimeInfo = RuntimeIdentifierInfo.parse(runtimeID), runtimeInfo.isIOS else { continue }
            for device in devices where device.isUsable {
                entries.append(DeviceEntry(
                    name: device.name,
                    runtimeDisplayName: runtimeInfo.displayName,
                    runtimeSortVersion: runtimeInfo.version,
                    udid: device.udid,
                    state: device.state,
                    availability: device.availabilitySummary
                ))
            }
        }

        if entries.isEmpty {
            IosSnapIO.printInfo("No available iOS simulators found.")
            return
        }

        entries.sort {
            if $0.runtimeSortVersion == $1.runtimeSortVersion {
                return $0.name.caseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.runtimeSortVersion < $1.runtimeSortVersion
        }

        IosSnapIO.printInfo("Available iOS simulators:")
        for entry in entries {
            var line = "- \(entry.name) (\(entry.runtimeDisplayName)) — \(entry.udid)"
            if let status = entry.statusSummary {
                line += " [\(status)]"
            }
            IosSnapIO.printInfo(line)
        }
    }

    private static func decodeDeviceList(from json: String) throws -> SimctlDeviceList {
        try JSONDecoder().decode(SimctlDeviceList.self, from: Data(json.utf8))
    }

    private struct DeviceEntry {
        let name: String
        let runtimeDisplayName: String
        let runtimeSortVersion: SemanticVersion
        let udid: String
        let state: String?
        let availability: String?

        var statusSummary: String? {
            var parts: [String] = []
            if let state = state, !state.isEmpty {
                parts.append(state)
            }
            if let availability = availability, !availability.isEmpty {
                parts.append(availability)
            }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: ", ")
        }
    }
}
