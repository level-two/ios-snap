import Foundation
import ArgumentParser

enum OrientationSetting: Equatable {
    case portrait
    case landscape
}

struct RenderLaunchConfiguration {
    let environment: [String: String]
    let arguments: [String]
    let outputFilename: String
}

struct RenderEnvironmentBuilder {
    let parameters: RenderParameters

    func makeLaunchConfiguration(sceneID: String?, statusOverride: StatusBarOverride?) throws -> RenderLaunchConfiguration {
        var environment: [String: String] = [:]
        var arguments: [String] = []

        if let appearance = try normalizedAppearance() {
            environment["SNAP_APPEARANCE"] = appearance
        }

        if let wait = try validatedWait() {
            environment["SNAP_WAIT"] = String(wait)
        }

        if let contentSize = try normalizedContentSize() {
            environment["SNAP_CONTENT_SIZE"] = contentSize
        }

        if let background = normalizedBackground() {
            environment["SNAP_BACKGROUND"] = background
        }

        let orientationSetting = try parseOrientation()
        if let sizeString = try normalizedSize(for: orientationSetting) {
            environment["SNAP_SIZE"] = sizeString
        } else if orientationSetting == .landscape {
            IosSnapIO.printInfo("[run] --orientation=landscape currently requires --size to specify explicit dimensions.")
        }

        if let scale = try validatedScale() {
            environment["SNAP_SCALE"] = String(scale)
        }

        if let sceneID {
            environment["SNAP_SCENE_ID"] = sceneID
        }

        if let override = statusOverride {
            environment["SNAP_STATUS_BAR"] = override.canonicalString()
        }

        let localeArgs = CommandValidators.localeArguments(locale: parameters.locale, region: parameters.region)
        if !localeArgs.isEmpty {
            arguments.append(contentsOf: localeArgs)
        }

        let outputFilename = "__snap.png"
        environment["SNAP_OUT_FILENAME"] = outputFilename

        return RenderLaunchConfiguration(environment: environment, arguments: arguments, outputFilename: outputFilename)
    }

    private func normalizedAppearance() throws -> String? {
        guard let appearance = parameters.appearance else { return nil }
        let normalized = appearance.lowercased()
        let allowed = ["light", "dark", "auto"]
        guard allowed.contains(normalized) else {
            throw ValidationError("Invalid --appearance value '\(appearance)'. Expected light|dark|auto.")
        }
        return normalized
    }

    private func validatedWait() throws -> Double? {
        guard let wait = parameters.wait else { return nil }
        guard wait >= 0 else {
            throw ValidationError("--wait must be non-negative.")
        }
        return wait
    }

    private func normalizedContentSize() throws -> String? {
        guard let contentSize = parameters.contentSize else { return nil }
        let normalized = contentSize.uppercased()
        let allowed = ["XS", "S", "M", "L", "XL", "XXL", "AX1", "AX2", "AX3", "AX4", "AX5"]
        guard allowed.contains(normalized) else {
            throw ValidationError("Invalid --content-size value '\(contentSize)'.")
        }
        return normalized
    }

    private func normalizedBackground() -> String? {
        guard let background = parameters.background else { return nil }
        let trimmed = background.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseOrientation() throws -> OrientationSetting? {
        guard let orientation = parameters.orientation else { return nil }
        let normalized = orientation.lowercased()
        switch normalized {
        case "portrait":
            return .portrait
        case "landscape":
            return .landscape
        default:
            throw ValidationError("Invalid --orientation value '\(orientation)'. Expected portrait|landscape.")
        }
    }

    private func normalizedSize(for orientation: OrientationSetting?) throws -> String? {
        guard let rawSize = parameters.size else { return nil }
        let trimmed = rawSize.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = CommandValidators.parseSize(trimmed) else {
            throw ValidationError("Invalid --size value '\(rawSize)'. Expected WIDTHxHEIGHT.")
        }

        let finalSize: (Double, Double)
        if orientation == .landscape {
            finalSize = (parsed.height, parsed.width)
        } else {
            finalSize = (parsed.width, parsed.height)
        }

        let widthString = CommandValidators.formatDimension(finalSize.0)
        let heightString = CommandValidators.formatDimension(finalSize.1)
        return "\(widthString)x\(heightString)"
    }

    private func validatedScale() throws -> Int? {
        guard let scale = parameters.scale else { return nil }
        guard scale == 2 || scale == 3 else {
            throw ValidationError("Invalid --scale value '\(scale)'. Expected 2 or 3.")
        }
        return scale
    }
}
