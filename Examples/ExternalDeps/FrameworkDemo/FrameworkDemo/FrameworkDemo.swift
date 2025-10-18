import SwiftUI

public struct FrameworkDemoView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            Text("Framework Demo")
                .font(.system(size: 30, weight: .bold))
            Text("Built from Xcode scheme via ios-snap")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.purple)
            Divider()
            HStack(spacing: 24) {
                badge(title: "Xcode", symbol: "hammer.fill", color: .orange)
                badge(title: "iphonesimulator", symbol: "ipad.and.iphone", color: .blue)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.95))
    }

    private func badge(title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(color.opacity(0.2))
            )
    }
}
