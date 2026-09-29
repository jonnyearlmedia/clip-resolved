import AppKit
import SwiftUI

struct SearchView: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore
    @State private var showSelectsConfirmation = false

    private static let visualSuggestions = ["Food", "Chef", "Exterior", "Interior", "Customers", "Atmosphere"]
    private static let spokenSuggestions = ["welcome", "thank you", "the sauce", "let's go", "introduce yourself"]

    private var suggestions: [String] {
        store.searchMode == .visual ? Self.visualSuggestions : Self.spokenSuggestions
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let project = store.selectedProject {
                queryPanel(project)
                Rectangle().fill(cr.border).frame(height: 1)
                results
            } else {
                CREmptyState(
                    title: "Open a project",
                    message: "Choose or create a project before searching indexed footage.",
                    symbol: "folder.badge.plus"
                )
            }
        }
        .background(cr.card)
        .task { await store.refreshSelectedProject() }
        .confirmationDialog("Create \(store.timelineName)?", isPresented: $showSelectsConfirmation) {
            Button("Create SELECTS and NOT SELECTED in Resolve") {
                Task { await store.createSelects() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Creates source-linked timelines from \(store.moments.count) handled ranges. The timelines reference the original media; no SELECTS video files are rendered.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            ProjectPicker(store: store)
            if let project = store.selectedProject {
                CRBadge(text: project.profile.rawValue, tone: .accent)
            }
            Spacer()
            Button("Manage Project") { store.selection = .project }
                .buttonStyle(CRSecondaryButtonStyle())
        }
        .padding(.horizontal, ClipResolvedDesign.pagePadding)
        .padding(.vertical, 14)
        .background(cr.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(cr.border).frame(height: 1) }
    }

    // MARK: Query

    private func queryPanel(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    projectIdentity(project)
                    Spacer()
                    projectMetrics(project)
                }
                VStack(alignment: .leading, spacing: 10) {
                    projectIdentity(project)
                    projectMetrics(project)
                }
            }

            Picker("Search", selection: $store.searchMode) {
                ForEach(SearchMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(cr.textTertiary)
                    TextField(
                        store.searchMode == .visual
                            ? "Search what appears on camera — e.g. all the luxury cars"
                            : "Search what was said — e.g. welcome to Osaka",
                        text: $store.query
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(cr.text)
                    .onSubmit { Task { await store.search() } }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(cr.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(cr.borderStrong) }

                Button("Search") { Task { await store.search() } }
                    .buttonStyle(CRPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(store.query.trimmingCharacters(in: .whitespaces).isEmpty || store.isBusy)
            }

            Text("Any new phrase works — footage was indexed once and stays queryable.")
                .font(CRFont.body(13))
                .foregroundStyle(cr.textTertiary)

            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        store.query = suggestion
                        Task { await store.search() }
                    } label: {
                        CRChip(text: suggestion, active: store.query.caseInsensitiveCompare(suggestion) == .orderedSame)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isBusy)
                }
                Spacer()
            }
        }
        .padding(ClipResolvedDesign.pagePadding)
        .frame(maxWidth: ClipResolvedDesign.contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        if store.moments.isEmpty {
            CREmptyState(
                title: "Search indexed footage",
                message: "Results are handled source ranges. New searches do not re-index your media.",
                symbol: "sparkle.magnifyingglass"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.moments) { moment in
                        resultRow(moment)
                    }
                }
                .padding(ClipResolvedDesign.pagePadding)
                .frame(maxWidth: ClipResolvedDesign.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            selectsBar
        }
    }

    private func resultRow(_ moment: MomentResult) -> some View {
        let start = moment.handledStart ?? moment.detectedStart
        let end = moment.handledEnd ?? moment.detectedEnd
        let evidence = ChatEvidence(
            sourcePath: moment.sourcePath,
            start: start,
            end: end,
            score: moment.score,
            transcript: moment.transcript
        )

        return CRCard(padding: 10) {
            HStack(spacing: 10) {
                Button {
                    preview(moment)
                } label: {
                    EvidenceThumbnailView(evidence: evidence, width: 120, height: 68)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(cr.text)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(moment.fileName) from \(start.editorTimecode) to \(end.editorTimecode)")
                .help("Preview this handled source range")

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(moment.fileName)
                            .font(CRFont.mono(12.5))
                            .foregroundStyle(cr.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(start.editorTimecode)–\(end.editorTimecode)")
                            .font(CRFont.mono(12))
                            .foregroundStyle(cr.textSecondary)
                    }

                    Text(moment.sourcePath)
                        .font(CRFont.mono(12))
                        .foregroundStyle(cr.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let transcript = moment.transcript, !transcript.isEmpty {
                        Text(transcript)
                            .font(CRFont.body(13))
                            .foregroundStyle(cr.textTertiary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        Button("Jump to source") { preview(moment) }
                            .buttonStyle(CRLinkButtonStyle())
                        Button("Reveal in Finder") { revealInFinder(moment) }
                            .buttonStyle(CRLinkButtonStyle())
                    }
                }
            }
        }
    }

    private var selectsBar: some View {
        HStack(spacing: 12) {
            TextField("SELECTS timeline name", text: $store.timelineName)
                .textFieldStyle(CRFieldStyle())
                .frame(maxWidth: 340)
            Text("\(store.moments.count) ranges")
                .font(CRFont.mono(11.5))
                .foregroundStyle(cr.textTertiary)
            Spacer()
            Button("Create Pair in Resolve →") { showSelectsConfirmation = true }
                .buttonStyle(CRPrimaryButtonStyle())
                .disabled(store.timelineName.isEmpty || store.isBusy)
                .help("Create the main SELECTS plus a NOT SELECTED review timeline covering all remaining source frames")
        }
        .padding(.horizontal, ClipResolvedDesign.pagePadding)
        .padding(.vertical, 14)
        .background(cr.bar)
        .overlay(alignment: .top) { Rectangle().fill(cr.border).frame(height: 1) }
    }

    // MARK: Actions

    private func preview(_ moment: MomentResult) {
        store.previewEvidence = ChatEvidence(
            sourcePath: moment.sourcePath,
            start: moment.handledStart ?? moment.detectedStart,
            end: moment.handledEnd ?? moment.detectedEnd,
            score: moment.score,
            transcript: moment.transcript
        )
    }

    private func revealInFinder(_ moment: MomentResult) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: moment.sourcePath)])
    }

    // MARK: Project summary

    private func projectIdentity(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .font(CRFont.display(22))
                .foregroundStyle(cr.text)
            Text(project.rootPath)
                .font(CRFont.mono(11))
                .foregroundStyle(cr.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func projectMetrics(_ project: ProjectRecord) -> some View {
        HStack(spacing: 24) {
            CRMetric(value: "\(project.indexedAssets)", label: "clips")
            CRMetric(value: "\(project.visualSamples)", label: "samples")
            CRMetric(value: "\(project.transcripts ?? 0)", label: "transcripts")
        }
    }
}
