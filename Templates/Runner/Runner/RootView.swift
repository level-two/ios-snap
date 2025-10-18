import SwiftUI
//__SNAP_IMPORTS__

struct RootView: View {
    let config: RunnerConfig

    var body: some View {
        SnapViewProvider.makeView(config: config)
    }
}

enum SnapViewProvider {
    private static var hasBootstrappedSnippet = false

    static func makeView(config: RunnerConfig) -> AnyView {
        if let sceneID = config.sceneID {
            bootstrapSnippetIfNeeded()
            guard let view = SnapshotRegistry.view(for: sceneID) else {
                RunnerExit.sceneMissing(sceneID)
            }
            return view
        }
        return makeSnippetView()
    }

    private static func bootstrapSnippetIfNeeded() {
        guard !hasBootstrappedSnippet else { return }
        hasBootstrappedSnippet = true
        _ = makeSnippetView()
    }

    private static func makeSnippetView() -> AnyView {
        //__SNAP_EXPR_START__
        return AnyView(Text("ios-snap placeholder"))
        //__SNAP_EXPR_END__
    }
}
