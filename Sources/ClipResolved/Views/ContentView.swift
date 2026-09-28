import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationSplitView {
            List(WorkspaceSection.allCases, selection: $store.selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Clip Resolved")
        } detail: {
            Group {
                switch store.selection {
                case .project: ProjectView(store: store)
                case .ingest: IngestView(store: store)
                case .chat: ChatView(store: store)
                case .search: SearchView(store: store)
                case .activity: ActivityView(store: store)
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatusBar(store: store)
            }
            .inspector(isPresented: Binding(
                get: { store.previewEvidence != nil },
                set: { if !$0 { store.previewEvidence = nil } }
            )) {
                if let evidence = store.previewEvidence {
                    FootagePreviewSidebarView(
                        evidence: evidence,
                        onClose: { store.previewEvidence = nil }
                    )
                    .id(evidence.id)
                    .inspectorColumnWidth(
                        min: ClipResolvedDesign.inspectorMinWidth,
                        ideal: ClipResolvedDesign.inspectorIdealWidth,
                        max: ClipResolvedDesign.inspectorMaxWidth
                    )
                }
            }
        }
        .alert("Clip Resolved", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }
}

private struct StatusBar: View {
    let store: AppStore
    var body: some View {
        HStack(spacing: 10) {
            if store.isBusy { ProgressView().controlSize(.small) }
            Text(store.progressMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(store.resolveMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
