import Foundation

enum SimulatorArchitecture: String {
    case arm64
    case x86_64

    static let host: SimulatorArchitecture = {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .arm64
        #endif
    }()

    var supportedArchitectures: Set<String> {
        switch self {
        case .arm64:
            return ["arm64"]
        case .x86_64:
            return ["x86_64"]
        }
    }

    var excludedArchitecturesValue: String? {
        switch self {
        case .arm64:
            return "x86_64"
        case .x86_64:
            return "arm64"
        }
    }
}
