func describeSimulatorError(_ error: SimulatorManager.ManagerError) -> String {
    switch error {
    case .missingDeviceArguments:
        return "Command requires either --device or --udid."
    case .udidNotFound(let udid):
        return "Simulator with UDID \(udid) not found. Run `ios-snap devices` to list available simulators."
    case .deviceNotFound(let message):
        return message
    case .deviceTypeNotFound(let name):
        return "Device type '\(name)' is not available in the installed runtimes."
    case .runtimeNotFound(let deviceType):
        return "No available iOS runtime supports device type \(deviceType). Install an iOS runtime in Xcode."
    case .simctlFailed(_, _, let stderr):
        return stderr.isEmpty ? "simctl command failed." : stderr
    case .deviceCreationFailed(let name, let reason):
        return "Failed to create simulator '\(name)': \(reason)"
    case .bootFailed(let reason):
        return "Failed to boot simulator: \(reason)"
    case .bootStatusFailed(let reason):
        return "Failed to monitor simulator boot status: \(reason)"
    case .statusBarOverrideFailed(let reason):
        return "Failed to apply status bar override: \(reason)"
    case .statusBarClearFailed(let reason):
        return "Failed to clear status bar override: \(reason)"
    }
}
