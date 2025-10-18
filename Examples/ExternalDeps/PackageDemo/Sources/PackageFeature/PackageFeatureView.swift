import SwiftUI

public struct PackageFeatureView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("Package Feature")
                .font(.system(size: 28, weight: .bold))
            Text("Rendered from SwiftPM package")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label("Dynamic build", systemImage: "shippingbox")
                Label("SwiftUI", systemImage: "swift")
            }
            .labelStyle(.iconWithTitle)
            .padding(.vertical, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
    }
}

private struct IconWithTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
        .font(.system(size: 16, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.15)))
    }
}

private extension LabelStyle where Self == IconWithTitleLabelStyle {
    static var iconWithTitle: IconWithTitleLabelStyle { IconWithTitleLabelStyle() }
}
