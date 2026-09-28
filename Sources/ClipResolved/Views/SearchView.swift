import SwiftUI

struct SearchView: View {
    @Bindable var store: AppStore
    @State private var showAddProject = false
    @State private var showSmartSelectsConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Project", selection: $store.selectedProjectID) {
                    ForEach(store.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .frame(maxWidth: 320)
                Button { showAddProject = true } label: { Label("Open Project", systemImage: "plus") }
                Spacer()
                Button("Index Footage") { Task { await store.indexSelectedProject() } }
                    .disabled(store.selectedProject == nil || store.isBusy)
                Button("Transcribe Audio") { Task { await store.transcribeSelectedProject() } }
                    .disabled(store.selectedProject == nil || store.isBusy)
                Button("Prepare Resolve") { Task { await store.prepareResolve() } }
                    .disabled(store.selectedProject == nil || store.isBusy)
                Button("Build Restaurant Selects") { showSmartSelectsConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedProject == nil || store.selectedProject?.indexedAssets == 0 || store.isBusy)
                    .help("Create the organized restaurant category package plus one complete NOT SELECTED review timeline")
            }
            .padding(16)

            Divider()

            if let project = store.selectedProject {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name).font(.title2.bold())
                            Text(project.rootPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Label("\(project.indexedAssets) clips", systemImage: "film.stack")
                        Label("\(project.visualSamples) samples", systemImage: "brain")
                        Label("\(project.transcripts ?? 0) transcripts", systemImage: "waveform")
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
        .sheet(isPresented: $showAddProject) {
            AddProjectView(store: store, isPresented: $showAddProject)
        }
        .confirmationDialog(
            "Build the restaurant SELECTS package?",
            isPresented: $showSmartSelectsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Create Complete Package in Resolve") {
                Task { await store.createSmartSelects() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Creates 00 ALL RAW FOOTAGE STRINGOUT, then Food, Exterior Storefront, Interior Dining Room, Drinks, Signage/Logo, Japanese Food Close Ups, and Sake Bottles in 00 TIMELINES / SELECTS, followed by ALL FOOTAGE NOT SELECTED REVIEW. Every range references the indexed original MP4s.")
        }
        .task { await store.refreshSelectedProject() }
    }
}

private struct AddProjectView: View {
    let store: AppStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var root = ""
    @State private var source = ""
    @State private var kind: ProjectKind = .client

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open Existing Project").font(.title2.bold())
            TextField("Project name", text: $name)
            Picker("Type", selection: $kind) {
                ForEach(ProjectKind.allCases) { Text($0.rawValue).tag($0) }
            }
            HStack {
                TextField("Project root", text: $root)
                Button("Choose…") {
                    if let url = FolderPicker.chooseFolder(prompt: "Choose the project root") {
                        root = url.path
                        if name.isEmpty { name = url.lastPathComponent }
                        let canonical = url.appendingPathComponent("Media/Osmo")
                        let raw = url.appendingPathComponent("RAW FOOTAGE")
                        if FileManager.default.fileExists(atPath: canonical.path) { source = canonical.path }
                        else if FileManager.default.fileExists(atPath: raw.path) { source = raw.path }
                    }
                }
            }
            HStack {
                TextField("Original footage folder", text: $source)
                Button("Choose…") {
                    if let url = FolderPicker.chooseFolder(prompt: "Choose the original footage folder", startingAt: root) { source = url.path }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Open") {
                    Task {
                        await store.addExistingProject(name: name, root: root, source: source, kind: kind)
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || root.isEmpty || source.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 680)
    }
}
