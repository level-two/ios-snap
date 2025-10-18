import Foundation

enum IosSnapIO {
    static func printInfo(_ message: String) {
        FileHandle.standardOutput.write((message + "\n").data(using: .utf8)!)
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
