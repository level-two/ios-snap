import Foundation

enum CommandValidators {
    static func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func parseImports(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseSize(_ raw: String) -> (width: Double, height: Double)? {
        let cleaned = raw
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0 else {
            return nil
        }
        return (width, height)
    }

    static func formatDimension(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value.rounded()))
        }
        return String(value)
    }

    static func localeArguments(locale: String?, region: String?) -> [String] {
        var args: [String] = []
        var languageCode: String?
        var localeValue: String?

        if let locale {
            let components = locale
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
            if let first = components.first {
                languageCode = String(first)
            }
            if components.count > 1 {
                localeValue = components[0...1].map { $0 }.joined(separator: "_")
            } else {
                localeValue = components.map { String($0) }.joined(separator: "_")
            }
        }

        if let region {
            let regionUpper = region.uppercased()
            if let language = languageCode {
                localeValue = "\(language)_\(regionUpper)"
            } else {
                languageCode = "en"
                localeValue = "en_\(regionUpper)"
            }
        }

        if let language = languageCode {
            args.append("-AppleLanguages")
            args.append("(\(language))")
        }

        if let localeValue {
            args.append("-AppleLocale")
            args.append(localeValue)
        }

        return args
    }
}
