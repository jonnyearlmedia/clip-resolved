import SwiftUI

struct ProjectView: View {
    @Bindable var store: AppStore
    @State private var showNewProject = false
    @State private var showAddProject = false
    @State private var showAddSource = false
    @State private var showPackageConfirmation = false
    @State private var showAudioSyncConfirmation = false
    @State private var showMulticamConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClipResolvedDesign.sectionSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        PageHeader(title: "Project", subtitle: "One editorial workspace, every camera and recorder, added whenever it becomes available.")
                        Spacer(minLength: 24)
                        projectControls
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        PageHeader(title: "Project", subtitle: "One editorial workspace, every camera and recorder, added whenever it becomes available.")
                        projectControls
                    }
                }

                if let project = store.selectedProject {
                    profileCard(project)
                    sourceCard(project)
                    readinessCard(project)
                    resolveCard(project)
                } else {
                    ContentUnavailableView(
                        "Open a project",
                        systemImage: "folder.badge.plus",
                        description: Text("Start with an existing footage folder or import camera media.")
                    )
                    Button("Open Existing Project") { showAddProject = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(ClipResolvedDesign.pagePadding)
            .frame(maxWidth: ClipResolvedDesign.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Project")
        .sheet(isPresented: $showNewProject) {
            NewProjectView(store: store, isPresented: $showNewProject)
        }
        .sheet(isPresented: $showAddProject) {
            AddProjectView(store: store, isPresented: $showAddProject)
        }
        .sheet(isPresented: $showAddSource) {
            AddSourceView(store: store, isPresented: $showAddSource)
        }
        .confirmationDialog("Build \(store.selectedProject?.profile.packageTitle ?? "SELECTS Package")?", isPresented: $showPackageConfirmation) {
            Button("Create Complete Package in Resolve") { Task { await store.createSmartSelects() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Creates a chronological all-footage stringout, named editorial SELECTS timelines, and a complete NOT SELECTED review timeline. All ranges reference the original media.")
        }
        .confirmationDialog("Sync external audio in Resolve?", isPresented: $showAudioSyncConfirmation) {
            Button("Sync by Waveform") { Task { await store.syncExternalAudio() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Resolve will match registered audio to imported camera clips by waveform while retaining embedded camera audio and video metadata.")
        }
        .confirmationDialog("Create a Resolve multicam clip?", isPresented: $showMulticamConfirmation) {
            Button("Sync Angles by Audio") { Task { await store.createMulticam(syncMode: "audio") } }
            Button("Sync Angles by Timecode") { Task { await store.createMulticam(syncMode: "timecode") } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Overlapping camera angles become multicam. Non-overlapping clips remain in the same chronological source collection and stringout.")
        }
        .task { await store.refreshSelectedProject() }
    }

    private var projectControls: some View {
        HStack(spacing: 10) {
            ProjectPicker(store: store)
            Button { showNewProject = true } label: {
                Label("New", systemImage: "plus")
            }
            Button { showAddProject = true } label: {
                Label("Open Existing", systemImage: "folder.badge.plus")
            }
        }
    }

    private func profileCard(_ project: ProjectRecord) -> some View {
        GroupBox("Editorial workflow") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Project type", selection: Binding(
                    get: { project.profile },
                    set: { store.setSelectedProjectProfile($0) }
                )) {
                    ForEach(ShootProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                Text(project.profile.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func sourceCard(_ project: ProjectRecord) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                if project.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Ready for the first card", systemImage: "sdcard")
                            .font(.headline)
                        Text("Open Import Media, choose this project as the destination, then scan and verify each camera or Mic 2 card one at a time. Everything stays attached to this project.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open Import Media") {
                            store.ingestDestinationProjectID = project.id
                            store.selection = .ingest
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(project.sources) { source in
                        HStack(spacing: 12) {
                            Image(systemName: source.kind == .camera ? "video.fill" : "waveform")
                                .foregroundStyle(source.kind == .camera ? Color.accentColor : .orange)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.label).fontWeight(.semibold)
                                Text(source.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(source.kind.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        if source.id != project.sources.last?.id { Divider() }
                    }
                }
            }
        } label: {
            HStack {
                Label("Sources", systemImage: "externaldrive.connected.to.line.below")
                Spacer()
                Button { showAddSource = true } label: { Label("Add Source", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func readinessCard(_ project: ProjectRecord) -> some View {
        GroupBox("Footage intelligence") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 28) { readinessMetrics(project); Spacer(); indexActions(project) }
                VStack(alignment: .leading, spacing: 14) { readinessMetrics(project); indexActions(project) }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private func readinessMetrics(_ project: ProjectRecord) -> some View {
        HStack(spacing: 24) {
            metric("\(project.indexedAssets)", "clips", "film.stack")
            metric("\(project.visualSamples)", "visual samples", "brain")
            metric("\(project.transcripts ?? 0)", "transcripts", "waveform")
        }
    }

    private func indexActions(_ project: ProjectRecord) -> some View {
        HStack(spacing: 10) {
            Button("Index New Media") { Task { await store.indexSelectedProject() } }
                .disabled(store.isBusy || project.sources.filter { $0.kind == .camera }.isEmpty)
            Button("Transcribe Interviews") { Task { await store.transcribeSelectedProject() } }
                .disabled(store.isBusy)
        }
    }

    private func resolveCard(_ project: ProjectRecord) -> some View {
        GroupBox("DaVinci Resolve") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prepare the project first. Then build a complete package, sync recorder audio, or create multicam angles without rendering duplicate SELECTS media.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { resolveActions(project) }
                    VStack(alignment: .leading, spacing: 10) { resolveActions(project) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private func resolveActions(_ project: ProjectRecord) -> some View {
        Button("Prepare Resolve") { Task { await store.prepareResolve() } }
            .disabled(store.isBusy || project.sources.filter { $0.kind == .camera }.isEmpty)
        Button("Build \(project.profile.packageTitle)") { showPackageConfirmation = true }
            .buttonStyle(.borderedProminent)
            .disabled(store.isBusy || project.indexedAssets == 0)
        Button("Sync External Audio") { showAudioSyncConfirmation = true }
            .disabled(store.isBusy || project.sources.isEmpty)
        Button("Create Multicam") { showMulticamConfirmation = true }
            .disabled(store.isBusy || project.sources.filter { $0.kind == .camera }.count < 2)
    }

    private func metric(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(value, systemImage: symbol).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct NewProjectView: View {
    let store: AppStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var parentRoot: String
    @State private var kind: ProjectKind = .client
    @State private var profile: ShootProfile = .event

    init(store: AppStore, isPresented: Binding<Bool>) {
        self.store = store
        _isPresented = isPresented
        _parentRoot = State(initialValue: store.activeProjectsRoot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "New Project",
                subtitle: "Create the project now. Add camera and Mic 2 cards to it later, in any order."
            )
            TextField("Project name", text: $name)
            Picker("Project ownership", selection: $kind) {
                ForEach(ProjectKind.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Editorial workflow", selection: $profile) {
                ForEach(ShootProfile.allCases) { Text($0.rawValue).tag($0) }
            }
            HStack {
                TextField("Active Projects folder", text: $parentRoot)
                Button("Choose…") {
                    if let url = FolderPicker.chooseFolder(prompt: "Choose the Active Projects folder", startingAt: parentRoot) {
                        parentRoot = url.path
                    }
                }
            }
            Text("The app creates a non-destructive project folder with separate Media and Audio storage. It does not need a card connected yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Create Project") {
                    store.activeProjectsRoot = parentRoot
                    store.createProject(name: name, parentRoot: parentRoot, kind: kind, profile: profile)
                    if store.errorMessage == nil { isPresented = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parentRoot.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 540, idealWidth: 680)
    }
}

struct AddProjectView: View {
    let store: AppStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var root = ""
    @State private var source = ""
    @State private var kind: ProjectKind = .client
    @State private var profile: ShootProfile = .communityStory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Open Existing Project", subtitle: "Keep the originals where they are and register the first camera source.")
            TextField("Project name", text: $name)
            Picker("Project ownership", selection: $kind) {
                ForEach(ProjectKind.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Editorial workflow", selection: $profile) {
                ForEach(ShootProfile.allCases) { Text($0.rawValue).tag($0) }
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
                        await store.addExistingProject(name: name, root: root, source: source, kind: kind, profile: profile)
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || root.isEmpty || source.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 540, idealWidth: 680)
    }
}

private struct AddSourceView: View {
    let store: AppStore
    @Binding var isPresented: Bool
    @State private var label = ""
    @State private var path = ""
    @State private var kind: ProjectSourceKind = .camera
    @State private var indexNow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Add Media Source", subtitle: "Add another camera or recorder now or later. Existing indexed footage stays intact.")
            Picker("Source type", selection: $kind) {
                ForEach(ProjectSourceKind.allCases) { Text($0.rawValue).tag($0) }
            }
            TextField(kind == .camera ? "Camera label, e.g. IPHONE" : "Recorder label, e.g. DJI MIC MINI", text: $label)
            HStack {
                TextField("Source folder", text: $path)
                Button("Choose…") {
                    if let url = FolderPicker.chooseFolder(prompt: "Choose the media source folder", startingAt: store.selectedProject?.rootPath ?? "") {
                        path = url.path
                        if label.isEmpty { label = ProjectRecord.inferSourceLabel(url.path, kind: kind) }
                    }
                }
            }
            if kind == .camera {
                Toggle("Index this source now", isOn: $indexNow)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Add Source") {
                    Task {
                        await store.addSource(label: label, path: path, kind: kind, indexNow: indexNow)
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || path.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 640)
    }
}
