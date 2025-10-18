import Foundation

struct StatusBarOverride {
    private let values: [String: String]
    let rawString: String

    init(values: [String: String], rawString: String) {
        self.values = values
        self.rawString = rawString
    }

    static func parse(from string: String) -> StatusBarOverride {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsed: [String: String] = [:]
        for token in trimmed.split(whereSeparator: \.isWhitespace) {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            parsed[parts[0].lowercased()] = parts[1]
        }
        return StatusBarOverride(values: parsed, rawString: trimmed)
    }

    func cliArguments() -> [String] {
        var args: [String] = []

        if let time = values["time"] { args.append(contentsOf: ["--time", time]) }
        if let wifi = values["wifi"] { args.append(contentsOf: ["--wifiBars", wifi]) }
        if let cellular = values["cellular"] { args.append(contentsOf: ["--cellularBars", cellular]) }
        if let data = values["data"] ?? values["network"] ?? values["mode"] {
            args.append(contentsOf: ["--dataNetwork", data])
        }
        if let battery = values["battery"] { args.append(contentsOf: ["--batteryLevel", battery]) }
        if let state = values["state"] { args.append(contentsOf: ["--batteryState", state]) }
        if let carrier = values["carrier"] { args.append(contentsOf: ["--carrierName", carrier]) }
        if let bluetooth = values["bluetooth"] { args.append(contentsOf: ["--bluetoothState", bluetooth]) }

        return args
    }

    func canonicalString() -> String {
        values
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    var isEmpty: Bool { values.isEmpty }
}

enum StatusBarOverrideParser {
    static func parse(_ raw: String?) -> StatusBarOverride? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let override = StatusBarOverride.parse(from: raw)
        return override.isEmpty ? nil : override
    }
}
