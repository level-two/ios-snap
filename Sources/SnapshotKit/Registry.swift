import CoreGraphics
import Foundation
import SwiftUI

/// Coordinates scene registration for registry mode renders.
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

    private static let queue = DispatchQueue(label: "ios.snap.snapshotregistry", attributes: .concurrent)
    private static var storage: [String: Entry] = [:]

    /// Register a scene by identifier. Subsequent calls with the same id replace the previous entry.
    public static func register<V: View>(
        _ id: String,
        size: SnapshotSize? = nil,
        summary: String? = nil,
        @ViewBuilder builder: @escaping () -> V
    ) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        let entry = Entry(
            scene: Scene(id: trimmedID, size: size, summary: summary),
            builder: { AnyView(builder()) }
        )

        queue.async(flags: .barrier) {
            storage[trimmedID] = entry
        }
    }

    /// Resolve a scene to an `AnyView`, if it has been registered.
    public static func view(for id: String) -> AnyView? {
        queue.sync { storage[id]?.builder() }
    }

    /// Retrieve metadata for a scene, if registered.
    public static func scene(for id: String) -> Scene? {
        queue.sync { storage[id]?.scene }
    }

    /// Return all registered scenes sorted by id.
    public static func allScenes() -> [Scene] {
        queue.sync { storage.values.map { $0.scene } }.sorted { $0.id < $1.id }
    }

    /// Reset registry contents. Mainly intended for tests.
    public static func reset() {
        queue.async(flags: .barrier) {
            storage.removeAll()
        }
    }
}

/// Captures logical size metadata for a scene.
public struct SnapshotSize: Hashable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let scale: Int

    public init(width: CGFloat, height: CGFloat, scale: Int = 3) {
        self.width = width
        self.height = height
        self.scale = max(1, scale)
    }

    /// Convenience helper for custom dimensions.
    public static func custom(width: CGFloat, height: CGFloat, scale: Int = 3) -> SnapshotSize {
        SnapshotSize(width: width, height: height, scale: scale)
    }

    /// Common presets for recent iPhone devices (points @ scale).
    public static let iPhone15Pro = SnapshotSize(width: 393, height: 852, scale: 3)
    public static let iPhone15ProMax = SnapshotSize(width: 430, height: 932, scale: 3)
    public static let iPhoneSE3 = SnapshotSize(width: 320, height: 568, scale: 2)
}

/// Property wrapper that registers the wrapped view into the SnapshotRegistry.
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
