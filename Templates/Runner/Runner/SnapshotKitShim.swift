import SwiftUI
import Foundation
import Dispatch

#if canImport(SnapshotKit)
@_exported import SnapshotKit
#else
// Minimal SnapshotKit shim for registry-mode when the real module is unavailable.
public enum SnapshotRegistry {
    public struct Scene: Hashable, Identifiable {
        public let id: String
        public let size: SnapshotSize?
        public let summary: String?

        public init(id: String, size: SnapshotSize? = nil, summary: String? = nil) {
            self.id = id
            self.size = size
            self.summary = summary
        }
    }

    private struct Entry {
        let scene: Scene
        let builder: () -> AnyView
    }

    private static var storage: [String: Entry] = [:]
    private static let queue = DispatchQueue(label: "ios.snap.snapshotregistry", attributes: .concurrent)

    public static func register<V: View>(
        _ id: String,
        size: SnapshotSize? = nil,
        summary: String? = nil,
        @ViewBuilder builder: @escaping () -> V
    ) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = Entry(scene: Scene(id: trimmed, size: size, summary: summary), builder: { AnyView(builder()) })
        queue.async(flags: .barrier) { storage[trimmed] = entry }
    }

    public static func view(for id: String) -> AnyView? {
        queue.sync { storage[id]?.builder() }
    }

    public static func scene(for id: String) -> Scene? {
        queue.sync { storage[id]?.scene }
    }

    public static func allScenes() -> [Scene] {
        queue.sync { storage.values.map { $0.scene } }.sorted { $0.id < $1.id }
    }

    public static func reset() {
        queue.async(flags: .barrier) { storage.removeAll() }
    }
}

public struct SnapshotSize: Hashable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let scale: Int

    public init(width: CGFloat, height: CGFloat, scale: Int = 3) {
        self.width = width
        self.height = height
        self.scale = max(1, scale)
    }

    public static func custom(width: CGFloat, height: CGFloat, scale: Int = 3) -> SnapshotSize {
        SnapshotSize(width: width, height: height, scale: scale)
    }

    public static let iPhone15Pro = SnapshotSize(width: 393, height: 852, scale: 3)
    public static let iPhone15ProMax = SnapshotSize(width: 430, height: 932, scale: 3)
    public static let iPhoneSE3 = SnapshotSize(width: 320, height: 568, scale: 2)
}

@propertyWrapper
public struct Snapshot<Value: View> {
    private let builder: () -> Value

    public var wrappedValue: Value { builder() }

    public init(
        _ id: String,
        size: SnapshotSize? = nil,
        summary: String? = nil,
        @ViewBuilder builder: @escaping () -> Value
    ) {
        SnapshotRegistry.register(id, size: size, summary: summary, builder: builder)
        self.builder = builder
    }
}
#endif
