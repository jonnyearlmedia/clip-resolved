import SwiftUI

struct SearchView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProjectPicker(store: store)
                if let project = store.selectedProject {
                    Text(project.profile.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Manage Project") { store.selection = .project }
            }
            .padding(16)

            Divider()

            if let project = store.selectedProject {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            projectIdentity(project)
                            Spacer()
                            projectMetrics(project)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            projectIdentity(project)
                            projectMetrics(project)
                        }
                    }

                    Picker("Search", selection: $store.searchMode) {
                        ForEach(SearchMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    HStack(spacing: 10) {
                        TextField(
                            store.searchMode == .visual
                                ? "Search what appears on camera — e.g. chef plating food"
                                : "Search what was said — e.g. welcome to Osaka",
                            text: $store.query
                        )
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .onSubmit { Task { await store.search() } }
                        Button("Search") { Task { await store.search() } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: [])
                            .disabled(store.query.trimmingCharacters(in: .whitespaces).isEmpty || store.isBusy)
                    }
                }
                .padding(20)

                Divider()

                if store.moments.isEmpty {
                    ContentUnavailableView(
                        "Search indexed footage",
                        systemImage: "sparkle.magnifyingglass",
                        description: Text("Results are handled source ranges. New searches do not re-index your media.")
                    )
                } else {
                    Table(store.moments) {
                        TableColumn("Preview") { moment in
                            Button {
                                store.previewEvidence = ChatEvidence(
                                    sourcePath: moment.sourcePath,
                                    start: moment.handledStart ?? moment.detectedStart,
                                    end: moment.handledEnd ?? moment.detectedEnd,
                                    score: moment.score,
                                    transcript: moment.transcript
                                )
                            } label: {
                                Image(systemName: "play.rectangle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Preview this handled source range")
                        }
                        .width(55)
                        TableColumn("Source") { moment in Text(moment.fileName).lineLimit(1) }
                        TableColumn("In") { moment in Text((moment.handledStart ?? moment.detectedStart).editorTimecode).monospacedDigit() }
                            .width(90)
                        TableColumn("Out") { moment in Text((moment.handledEnd ?? moment.detectedEnd).editorTimecode).monospacedDigit() }
                            .width(90)
                        TableColumn("Score") { moment in Text(moment.score, format: .number.precision(.fractionLength(3))).monospacedDigit() }
                            .width(70)
                        TableColumn("Match") { moment in
                            Text(moment.transcript ?? (store.searchMode == .visual ? store.query : ""))
                                .lineLimit(2)
                        }
                    }

                    Divider()
                    HStack {
                        TextField("SELECTS timeline name", text: $store.timelineName)
                        Text("\(store.moments.count) ranges")
                            .foregroundStyle(.secondary)
                        Button("Create Pair in Resolve") { Task { await store.createSelects() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.timelineName.isEmpty || store.isBusy)
                            .help("Create the main SELECTS plus a NOT SELECTED review timeline covering all remaining source frames")
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Open a project", systemImage: "folder.badge.plus")
            }
        }
        .navigationTitle("Footage Search")
        .task { await store.refreshSelectedProject() }
    }

    private func projectIdentity(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name).font(.title2.bold())
            Text(project.rootPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func projectMetrics(_ project: ProjectRecord) -> some View {
        HStack(spacing: 16) {
            Label("\(project.indexedAssets) clips", systemImage: "film.stack")
            Label("\(project.visualSamples) samples", systemImage: "brain")
            Label("\(project.transcripts ?? 0) transcripts", systemImage: "waveform")
        }
        .font(.callout)
    }
}
