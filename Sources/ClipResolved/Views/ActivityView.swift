import SwiftUI

struct ActivityView: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClipResolvedDesign.sectionSpacing) {
                PageHeader(
                    title: store.isBusy ? "Working on it" : "Projects and activity",
                    subtitle: "Copy, verification, and indexing happen per take as it completes. Once a shoot is indexed you can query it however you like, later, without reanalyzing it."
                )

                currentJob
                readyProjects
                activityLog
            }
            .padding(ClipResolvedDesign.pagePadding)
            .frame(maxWidth: ClipResolvedDesign.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(cr.card)
    }

    // MARK: Current job

    private var currentJob: some View {
        CRCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(store.progressMessage)
                        .font(CRFont.heading(13.5))
                        .foregroundStyle(cr.text)
                    Spacer()
                    CRBadge(
                        text: store.isBusy ? "Running" : "Idle",
                        tone: store.isBusy ? .accent : .neutral
                    )
                }

                if store.isBusy {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(cr.accent)
                        .accessibilityLabel("Current operation in progress")
                } else {
                    CRProgressBar(fraction: 0, tint: cr.textTertiary)
                }

                HStack(spacing: 6) {
                    CRChip(text: "Copy", active: activeStage == "copy")
                    CRChip(text: "Verify", active: activeStage == "verify")
                    CRChip(text: "Index", active: activeStage == "index")
                    CRChip(text: "Transcript", active: activeStage == "transcript")
                    Spacer()
                    Text(store.resolveMessage)
                        .font(CRFont.mono(11))
                        .foregroundStyle(cr.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: Ready projects

    @ViewBuilder private var readyProjects: some View {
        if !store.projects.isEmpty {
            CRSection("Projects") {
                VStack(spacing: 0) {
                    ForEach(store.projects) { project in
                        let hasCameraSource = project.sources.contains {
                            $0.kind == .camera && !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        let visualPreparationCurrent = store.isVisualPreparationCurrent(project)
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name)
                                    .font(CRFont.heading(13.5))
                                    .foregroundStyle(cr.text)
                                Text("\(project.indexedAssets) clips · \(project.visualSamples) samples · \(project.transcripts ?? 0) transcripts")
                                    .font(CRFont.mono(11))
                                    .foregroundStyle(cr.textTertiary)
                            }
                            Spacer()
                            CRBadge(
                                text: visualPreparationCurrent
                                    ? "Visual SELECTS ready ✓"
                                    : (!hasCameraSource
                                        ? "Needs camera media"
                                        : (project.indexedAssets == 0 ? "Index first" : "Needs visual SELECTS")),
                                tone: visualPreparationCurrent ? .success : .warm
                            )
                            Button("Review Project →") {
                                store.selectedProjectID = project.id
                                store.selection = .project
                            }
                            .buttonStyle(CRPrimaryButtonStyle())
                            .disabled(store.isBusy)
                        }
                        .padding(.vertical, 10)
                        if project.id != store.projects.last?.id {
                            Rectangle().fill(cr.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: Log

    private var activityLog: some View {
        CRSection("Activity") {
            if store.activity.isEmpty {
                Text("Nothing has happened yet. Plug in a card, or open a project and index it.")
                    .font(CRFont.body(13))
                    .foregroundStyle(cr.textTertiary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(store.activity) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Self.clock.string(from: entry.date))
                                .font(CRFont.mono(11.5))
                                .foregroundStyle(cr.textTertiary)
                            Text(entry.message)
                                .font(CRFont.mono(11.5))
                                .foregroundStyle(entry.isError ? cr.danger : cr.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var activeStage: String? {
        guard store.isBusy else { return nil }
        let message = store.progressMessage.lowercased()
        if message.contains("cop") || message.contains("offload") { return "copy" }
        if message.contains("verif") || message.contains("checksum") { return "verify" }
        if message.contains("index") || message.contains("search") || message.contains("analy") { return "index" }
        if message.contains("transcri") || message.contains("speech") { return "transcript" }
        return nil
    }
}
