import Foundation

protocol SimulatorManaging {
    func resolveDevice(udid: String?, deviceName: String?) throws -> SimulatorManager.ResolvedDevice
    func bootIfNeeded(udid: String) throws
    func applyStatusBarOverride(udid: String, override: StatusBarOverride) throws
    func clearStatusBarOverride(udid: String) throws
}

struct SimulatorManager: SimulatorManaging {
    private let decoder = JSONDecoder()

    struct ResolvedDevice {
        let name: String
        let udid: String
        let runtime: RuntimeIdentifierInfo
        let deviceTypeIdentifier: String
    }

    enum ManagerError: Error {
        case missingDeviceArguments
        case udidNotFound(String)
        case deviceNotFound(String)
        case deviceTypeNotFound(String)
        case runtimeNotFound(String)
        case simctlFailed(command: [String], status: Int32, stderr: String)
        case deviceCreationFailed(String, String)
        case bootFailed(String)
        case bootStatusFailed(String)
        case statusBarOverrideFailed(String)
        case statusBarClearFailed(String)
    }

    func resolveDevice(udid: String?, deviceName: String?) throws -> ResolvedDevice {
        if let udid = udid {
            return try resolveByUDID(udid)
        }
        guard let name = deviceName else {
            throw ManagerError.missingDeviceArguments
        }
        if let existing = try findExistingDevice(named: name) {
            return existing
        }
        return try createDevice(named: name)
    }

    func bootIfNeeded(udid: String) throws {
        let bootCommand = ["xcrun", "simctl", "boot", udid]
        let bootResult = try Shell.run(bootCommand)
        if bootResult.status != 0 {
            let stderr = bootResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = bootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = [stderr, stdout].filter { !$0.isEmpty }.joined(separator: "\n")
            if !combined.contains("Unable to boot device in current state: Booted") {
                throw ManagerError.bootFailed(combined.isEmpty ? "Unknown boot failure" : combined)
            }
        }

        let statusCommand = ["xcrun", "simctl", "bootstatus", udid, "-b"]
        let statusResult = try Shell.run(statusCommand)
        if statusResult.status != 0 {
            let message = statusResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ManagerError.bootStatusFailed(message.isEmpty ? "Boot status command failed" : message)
        }
    }

    func applyStatusBarOverride(udid: String, override: StatusBarOverride) throws {
        let args = override.cliArguments()
        guard !args.isEmpty else { return }
        let command = ["xcrun", "simctl", "status_bar", udid, "override"] + args
        let result = try Shell.run(command)
        if result.status != 0 {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ManagerError.statusBarOverrideFailed(message.isEmpty ? "status_bar override failed" : message)
        }
    }

    func clearStatusBarOverride(udid: String) throws {
        let command = ["xcrun", "simctl", "status_bar", udid, "clear"]
        let result = try Shell.run(command)
        if result.status != 0 {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ManagerError.statusBarClearFailed(message.isEmpty ? "status_bar clear failed" : message)
        }
    }
}

extension SimulatorManager {
    private func resolveByUDID(_ udid: String) throws -> ResolvedDevice {
        let list = try fetchDeviceList()
        for (runtimeID, devices) in list.devices {
            guard let runtimeInfo = RuntimeIdentifierInfo.parse(runtimeID), runtimeInfo.isIOS else { continue }
            if let device = devices.first(where: { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }) {
                guard let type = device.deviceTypeIdentifier else {
                    throw ManagerError.deviceNotFound("Device \(udid) missing deviceTypeIdentifier")
                }
                return ResolvedDevice(name: device.name, udid: device.udid, runtime: runtimeInfo, deviceTypeIdentifier: type)
            }
        }
        throw ManagerError.udidNotFound(udid)
    }

    private func findExistingDevice(named name: String) throws -> ResolvedDevice? {
        let list = try fetchDeviceList()
        var bestMatch: (device: SimctlDevice, runtime: RuntimeIdentifierInfo)?
        for (runtimeID, devices) in list.devices {
            guard let runtimeInfo = RuntimeIdentifierInfo.parse(runtimeID), runtimeInfo.isIOS else { continue }
            guard let match = devices.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.isUsable }) else {
                continue
            }
            if let current = bestMatch {
                if runtimeInfo.version > current.runtime.version {
                    bestMatch = (match, runtimeInfo)
                }
            } else {
                bestMatch = (match, runtimeInfo)
            }
        }
        if let bestMatch {
            guard let type = bestMatch.device.deviceTypeIdentifier else {
                return nil
            }
            return ResolvedDevice(
                name: bestMatch.device.name,
                udid: bestMatch.device.udid,
                runtime: bestMatch.runtime,
                deviceTypeIdentifier: type
            )
        }
        return nil
    }

    private func createDevice(named name: String) throws -> ResolvedDevice {
        let deviceTypes = try fetchDeviceTypes()
        guard let deviceType = deviceTypes.devicetypes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && ($0.productFamily == nil || $0.productFamily == "iPhone" || $0.productFamily == "iPad") }) else {
            throw ManagerError.deviceTypeNotFound(name)
        }

        let runtime = try selectRuntime(for: deviceType.identifier)

        let command = ["xcrun", "simctl", "create", name, deviceType.identifier, runtime.rawIdentifier]
        let result = try Shell.run(command)
        if result.status != 0 {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ManagerError.deviceCreationFailed(name, message.isEmpty ? "simctl create failed" : message)
        }
        let createdUDID = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !createdUDID.isEmpty else {
            throw ManagerError.deviceCreationFailed(name, "simctl create did not return a UDID")
        }
        return try resolveByUDID(createdUDID)
    }

    private func selectRuntime(for deviceTypeIdentifier: String) throws -> RuntimeIdentifierInfo {
        let runtimeList = try fetchRuntimeList()
        let candidates: [(RuntimeIdentifierInfo, SimctlRuntime)] = runtimeList.runtimes.compactMap { runtime in
            guard let info = RuntimeIdentifierInfo.parse(runtime.identifier), info.isIOS else { return nil }
            guard runtime.isAvailable ?? true else { return nil }

            if let supported = runtime.supportedDeviceTypes,
               supported.contains(where: { $0.identifier == deviceTypeIdentifier }) {
                return (info, runtime)
            }

            if runtime.supportedDeviceTypes == nil {
                return (info, runtime)
            }

            return nil
        }

        guard let best = candidates.max(by: { $0.0.version < $1.0.version }) else {
            throw ManagerError.runtimeNotFound(deviceTypeIdentifier)
        }
        return best.0
    }

    private func fetchDeviceList() throws -> SimctlDeviceList {
        try decodeSimctl(command: ["xcrun", "simctl", "list", "--json", "devices"], as: SimctlDeviceList.self)
    }

    private func fetchRuntimeList() throws -> SimctlRuntimeList {
        try decodeSimctl(command: ["xcrun", "simctl", "list", "--json", "runtimes"], as: SimctlRuntimeList.self)
    }

    private func fetchDeviceTypes() throws -> SimctlDeviceTypeList {
        try decodeSimctl(command: ["xcrun", "simctl", "list", "--json", "devicetypes"], as: SimctlDeviceTypeList.self)
    }

    private func decodeSimctl<T: Decodable>(command: [String], as type: T.Type) throws -> T {
        let result = try Shell.run(command)
        if result.status != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ManagerError.simctlFailed(command: command, status: result.status, stderr: stderr)
        }
        do {
            return try decoder.decode(T.self, from: Data(result.stdout.utf8))
        } catch {
            throw ManagerError.simctlFailed(command: command, status: result.status, stderr: "JSON decode failed: \(error.localizedDescription)")
        }
    }
}
