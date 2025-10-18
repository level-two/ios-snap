import SwiftUI
#if canImport(SnapshotKit)
import SnapshotKit
#endif

private func registerSnapshots() {
    SnapshotRegistry.register("demo/hello", size: .iPhone15Pro, summary: "Sample greeting screen") {
        DemoHelloView()
    }

    SnapshotRegistry.register("demo/error", size: .iPhoneSE3, summary: "Compact error placeholder") {
        DemoErrorView()
    }
}

private struct DemoHelloView: View {
    var body: some View {
        Text("Hello from registry mode!")
            .font(.system(size: 28, weight: .bold))
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.blue.opacity(0.12))
            )
            .padding()
    }
}

private struct DemoErrorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Please try again later.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.red.opacity(0.1))
        )
        .padding()
    }
}

func makeView() -> some View {
    registerSnapshots()
    return EmptyView()
}
