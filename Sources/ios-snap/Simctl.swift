import Foundation

struct SimctlDeviceList: Decodable {
    let devices: [String: [SimctlDevice]]
}

struct SimctlDevice: Decodable {
    let udid: String
    let name: String
    let isAvailable: Bool?
    let availability: String?
    let availabilityError: String?
    let state: String?
    let deviceTypeIdentifier: String?
}

struct SimctlRuntimeList: Decodable {
    let runtimes: [SimctlRuntime]
}

struct SimctlRuntime: Decodable {
    struct SupportedDeviceType: Decodable {
        let identifier: String
        let name: String
        let productFamily: String?
    }

    let identifier: String
    let name: String
    let version: String?
    let isAvailable: Bool?
    let platform: String?
    let supportedDeviceTypes: [SupportedDeviceType]?
}

struct SimctlDeviceTypeList: Decodable {
    let devicetypes: [SimctlDeviceType]
}

struct SimctlDeviceType: Decodable {
    let identifier: String
    let name: String
    let productFamily: String?
}

struct RuntimeIdentifierInfo {
    enum Platform: String {
        case iOS
        case tvOS
        case watchOS
        case visionOS
        case unknown
    }

    let rawIdentifier: String
    let platform: Platform
    let version: SemanticVersion

    var displayName: String {
        guard platform != .unknown else { return rawIdentifier }
        return "\(platform.rawValue) \(version.description)"
    }
}

struct SemanticVersion: Comparable {
    let components: [Int]

    init(_ comps: [Int]) {
        self.components = comps
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for idx in 0..<count {
            let left = idx < lhs.components.count ? lhs.components[idx] : 0
            let right = idx < rhs.components.count ? rhs.components[idx] : 0
            if left < right { return true }
            if left > right { return false }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.components == rhs.components
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }
}

extension RuntimeIdentifierInfo {
    static func parse(_ raw: String) -> RuntimeIdentifierInfo? {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        guard raw.hasPrefix(prefix) else { return nil }
        let suffix = raw.dropFirst(prefix.count)
        let parts = suffix.split(separator: "-")
        guard let platformRaw = parts.first else { return nil }
        let platform = Platform(rawValue: String(platformRaw)) ?? .unknown
        let versionParts = parts.dropFirst().compactMap { Int($0) }
        guard !versionParts.isEmpty else {
            return RuntimeIdentifierInfo(rawIdentifier: raw, platform: platform, version: SemanticVersion([0, 0]))
        }
        return RuntimeIdentifierInfo(
            rawIdentifier: raw,
            platform: platform,
            version: SemanticVersion(versionParts)
        )
    }
}

extension SimctlDevice {
    var isUsable: Bool {
        if let isAvailable, isAvailable == false {
            return false
        }
        if let availabilityError, !availabilityError.isEmpty {
            return false
        }
        if let availability {
            let normalized = availability.lowercased()
            if normalized.contains("unavailable") {
                return false
            }
        }
        return true
    }

    var availabilitySummary: String? {
        if let availabilityError, !availabilityError.isEmpty {
            return availabilityError
        }
        if let availability = availability?.trimmingCharacters(in: CharacterSet(charactersIn: "() \t\n\r")), !availability.isEmpty {
            return availability
        }
        if let isAvailable {
            return isAvailable ? "available" : "unavailable"
        }
        return nil
    }
}

extension RuntimeIdentifierInfo {
    var isIOS: Bool { platform == .iOS }
}
