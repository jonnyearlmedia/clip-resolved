import SwiftUI

struct ProjectView: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore
    @State private var showNewProject = false
    @State private var showAddProject = false
    @State private var showAddSource = false
    @State private var showPackageConfirmation = false
    @State private var showPrepareResolveConfirmation = false
    @State private var showAudioSyncConfirmation = false
    @State private var showMulticamConfirmation = false
    @State private var organizerProject: ProjectRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClipResolvedDesign.sectionSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        PageHeader(title: "Project", subtitle: "One editorial workspace, every camera and recorder, added whenever it becomes available.")
                        Spacer(minLength: 24)
                        projectControls
                    }
                    VStack(alignment: .leading, spacing: 14) {
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
                    CRCard(padding: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Open a project")
                                .font(CRFont.title(18))
                                .foregroundStyle(cr.text)
                            Text("Start with an existing footage folder, or import camera media to create one.")
                                .font(CRFont.body(13))
                                .foregroundStyle(cr.textSecondary)
                            Button("Open Existing Project") { showAddProject = true }
                                .buttonStyle(CRPrimaryButtonStyle())
                        }
                    }
                }
            }
            .padding(ClipResolvedDesign.pagePadding)
            .frame(maxWidth: ClipResolvedDesign.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(cr.card)
        .sheet(isPresented: $showNewProject) {
            NewProjectView(store: store, isPresented: $showNewProject).environment(\.cr, cr)
        }
        .sheet(isPresented: $showAddProject) {
            AddProjectView(store: store, isPresented: $showAddProject).environment(\.cr, cr)
        }
        .sheet(isPresented: $showAddSource) {
            AddSourceView(store: store, isPresented: $showAddSource).environment(\.cr, cr)
        }
        .sheet(item: $organizerProject) { project in
            ProjectMediaOrganizerView(
                store: store,
                project: project,
                isPresented: Binding(
                    get: { organizerProject != nil },
                    set: { if !$0 { organizerProject = nil } }
                )
            )
            .environment(\.cr, cr)
        }
        .confirmationDialog("Build visual SELECTS for \(store.selectedProject?.name ?? "this project")?", isPresented: $showPackageConfirmation) {
            Button("Create Visual SELECTS Package in Resolve") { Task { await store.createSmartSelects() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Creates a chronological all-footage stringout, one merged ALL B-ROLL SELECTS timeline, visual category SELECTS, and a complete NOT SELECTED review timeline from the indexed camera footage. Narration SELECTS are separate. All ranges reference the original media.")
        }
        .confirmationDialog("Prepare this project in DaVinci Resolve?", isPresented: $showPrepareResolveConfirmation) {
            Button("Prepare Resolve Project") { Task { await store.prepareResolve() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Creates or updates the Resolve project and source bins. It does not render duplicate media or create editorial SELECTS timelines.")
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
            Button("New") { showNewProject = true }
                .buttonStyle(CRSecondaryButtonStyle())
            Button("Open Existing") { showAddProject = true }
                .buttonStyle(CRSecondaryButtonStyle())
        }
    }

    private func profileCard(_ project: ProjectRecord) -> some View {
        CRSection("Editorial workflow") {
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
                .labelsHidden()

                Text(project.profile.summary)
                    .font(CRFont.body(13))
                    .foregroundStyle(cr.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sourceCard(_ project: ProjectRecord) -> some View {
        CRSection(
            "Sources",
            trailing: AnyView(
                HStack(spacing: 12) {
                    Button("Organize Imported Media") { organizerProject = project }
                        .buttonStyle(CRSecondaryButtonStyle())
                        .disabled(cameraSources(in: project).isEmpty || store.isBusy)
                    Button("+ Add Source") { showAddSource = true }
                        .buttonStyle(CRLinkButtonStyle())
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if project.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ready for the first card")
                            .font(CRFont.heading(14))
                            .foregroundStyle(cr.text)
                        Text("Open Import Media, choose this project as the destination, then scan and verify each camera or recorder card one at a time. Everything stays attached to this project.")
                            .font(CRFont.body(13))
                            .foregroundStyle(cr.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Import Media") {
                            store.ingestDestinationProjectID = project.id
                            store.selection = .ingest
                        }
                        .buttonStyle(CRPrimaryButtonStyle())
                    }
                } else {
                    ForEach(project.sources) { source in
                        HStack(spacing: 12) {
                            Image(systemName: source.kind == .camera ? "video.fill" : "waveform")
                                .foregroundStyle(source.kind == .camera ? cr.accent : cr.warm)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.label)
                                    .font(CRFont.heading(13))
                                    .foregroundStyle(cr.text)
                                Text(source.path)
                                    .font(CRFont.mono(11))
                                    .foregroundStyle(cr.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            CRBadge(text: source.kind.rawValue, tone: source.kind == .camera ? .accent : .warm)
                        }
                        .padding(.vertical, 10)
                        if source.id != project.sources.last?.id {
                            Rectangle().fill(cr.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func readinessCard(_ project: ProjectRecord) -> some View {
        CRSection("Footage intelligence") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 28) { readinessMetrics(project); Spacer(); indexActions(project) }
                VStack(alignment: .leading, spacing: 16) { readinessMetrics(project); indexActions(project) }
            }
        }
    }

    @ViewBuilder private func readinessMetrics(_ project: ProjectRecord) -> some View {
        HStack(spacing: 28) {
            CRMetric(value: "\(project.indexedAssets)", label: "clips")
            CRMetric(value: "\(project.visualSamples)", label: "visual samples")
            CRMetric(value: "\(project.transcripts ?? 0)", label: "transcripts")
        }
    }

    private func indexActions(_ project: ProjectRecord) -> some View {
        HStack(spacing: 10) {
            Button("Index New Media") { Task { await store.indexSelectedProject() } }
                .buttonStyle(CRSecondaryButtonStyle())
                .disabled(store.isBusy || cameraSources(in: project).isEmpty)
            Button("Transcribe Spoken Audio") { Task { await store.transcribeSelectedProject() } }
                .buttonStyle(CRSecondaryButtonStyle())
                .disabled(store.isBusy || project.sources.isEmpty)
        }
    }

    private func resolveCard(_ project: ProjectRecord) -> some View {
        CRSection("DaVinci Resolve") {
            VStack(alignment: .leading, spacing: 14) {
                visualPreparationStatus(project)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { resolveActions(project) }
                    VStack(alignment: .leading, spacing: 10) { resolveActions(project) }
                }
            }
        }
    }

    private func visualPreparationStatus(_ project: ProjectRecord) -> some View {
        let current = store.isVisualPreparationCurrent(project)
        let reviewedOnly = store.hasCurrentReviewedVisualSearch(project)
        let stale = project.visualPreparation != nil && !current && !reviewedOnly
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: current ? "checkmark.seal.fill" : "film.stack")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(current ? cr.success : cr.warm)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(
                    current
                        ? "Automatic visual package is current"
                        : (reviewedOnly
                            ? "Organized visual SELECTS still needed"
                            : (stale ? "New footage needs an updated visual package" : "Visual footage needs automatic organization"))
                )
                    .font(CRFont.heading(16))
                    .foregroundStyle(cr.text)
                Text(
                    current
                        ? "The raw stringout, merged ALL B-ROLL SELECTS, shoot-aware category SELECTS, and global NOT SELECTED review cover all \(project.indexedAssets) indexed camera clips."
                        : (reviewedOnly
                            ? "The reviewed B-roll search answers one question, but it is not the initial organized package. Build the full package to separate interiors, exteriors, people, process, details, and other project-specific categories automatically."
                            : "\(project.indexedAssets) camera clips are indexed, but indexing is only the searchable layer. Build the full shoot-aware package before treating the visual footage as editorially prepared.")
                )
                    .font(CRFont.body(14))
                    .foregroundStyle(cr.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(current ? cr.successSoft : cr.warmSoft, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder((current ? cr.success : cr.warm).opacity(0.35))
        }
    }

    @ViewBuilder private func resolveActions(_ project: ProjectRecord) -> some View {
        Button("Prepare Resolve") { showPrepareResolveConfirmation = true }
            .buttonStyle(CRSecondaryButtonStyle())
            .disabled(store.isBusy || cameraSources(in: project).isEmpty)
        if store.isVisualPreparationCurrent(project) {
            Button("Rebuild Full Visual Package…") { showPackageConfirmation = true }
                .buttonStyle(CRSecondaryButtonStyle())
                .disabled(store.isBusy || project.indexedAssets == 0)
        } else {
            Button("Build Full Visual Package…") { showPackageConfirmation = true }
                .buttonStyle(CRPrimaryButtonStyle())
                .disabled(store.isBusy || project.indexedAssets == 0)
        }
        Button("Sync External Audio") { showAudioSyncConfirmation = true }
            .buttonStyle(CRSecondaryButtonStyle())
            .disabled(store.isBusy || project.sources.isEmpty)
        Button("Create Multicam") { showMulticamConfirmation = true }
            .buttonStyle(CRSecondaryButtonStyle())
            .disabled(store.isBusy || cameraSources(in: project).count < 2)
    }

    private func cameraSources(in project: ProjectRecord) -> [ProjectSourceRecord] {
        project.sources.filter {
            $0.kind == .camera && !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

// MARK: - Sheets

private struct SheetChrome<Content: View>: View {
    @Environment(\.cr) private var cr
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(26)
            .background(cr.card)
    }
}

private struct NewProjectView: View {
    @Environment(\.cr) private var cr
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
        SheetChrome {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    title: "New Project",
                    subtitle: "Create the project now. Add camera and recorder cards to it later, in any order."
                )
                TextField("Project name", text: $name)
                    .textFieldStyle(CRFieldStyle())
                Picker("Project ownership", selection: $kind) {
                    ForEach(ProjectKind.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Editorial workflow", selection: $profile) {
                    ForEach(ShootProfile.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    TextField("Active Projects folder", text: $parentRoot)
                        .textFieldStyle(CRFieldStyle())
                    Button("Choose…") {
                        if let url = FolderPicker.chooseFolder(prompt: "Choose the Active Projects folder", startingAt: parentRoot) {
                            parentRoot = url.path
                        }
                    }
                    .buttonStyle(CRSecondaryButtonStyle())
                }
                Text("The app creates a non-destructive project folder with separate Media and Audio storage. It does not need a card connected yet.")
                    .font(CRFont.body(13))
                    .foregroundStyle(cr.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(CRSecondaryButtonStyle())
                    Button("Create Project") {
                        store.activeProjectsRoot = parentRoot
                        store.createProject(name: name, parentRoot: parentRoot, kind: kind, profile: profile)
                        if store.errorMessage == nil { isPresented = false }
                    }
                    .buttonStyle(CRPrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parentRoot.isEmpty)
                }
            }
        }
        .frame(minWidth: 540, idealWidth: 680)
    }
}

struct AddProjectView: View {
    @Environment(\.cr) private var cr
    let store: AppStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var root = ""
    @State private var source = ""
    @State private var kind: ProjectKind = .client
    @State private var profile: ShootProfile = .communityStory

    var body: some View {
        SheetChrome {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Open Existing Project", subtitle: "Keep the originals where they are and register the first camera source.")
                TextField("Project name", text: $name)
                    .textFieldStyle(CRFieldStyle())
                Picker("Project ownership", selection: $kind) {
                    ForEach(ProjectKind.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Editorial workflow", selection: $profile) {
                    ForEach(ShootProfile.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    TextField("Project root", text: $root)
                        .textFieldStyle(CRFieldStyle())
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
                    .buttonStyle(CRSecondaryButtonStyle())
                }
                HStack {
                    TextField("Original footage folder", text: $source)
                        .textFieldStyle(CRFieldStyle())
                    Button("Choose…") {
                        if let url = FolderPicker.chooseFolder(prompt: "Choose the original footage folder", startingAt: root) { source = url.path }
                    }
                    .buttonStyle(CRSecondaryButtonStyle())
                }
                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(CRSecondaryButtonStyle())
                    Button("Open") {
                        Task {
                            await store.addExistingProject(name: name, root: root, source: source, kind: kind, profile: profile)
                            isPresented = false
                        }
                    }
                    .buttonStyle(CRPrimaryButtonStyle())
                    .disabled(name.isEmpty || root.isEmpty || source.isEmpty)
                }
            }
        }
        .frame(minWidth: 540, idealWidth: 680)
    }
}

private struct AddSourceView: View {
    @Environment(\.cr) private var cr
    let store: AppStore
    @Binding var isPresented: Bool
    @State private var label = ""
    @State private var path = ""
    @State private var kind: ProjectSourceKind = .camera
    @State private var indexNow = true

    var body: some View {
        SheetChrome {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Add Media Source", subtitle: "Add another camera or recorder now or later. Existing indexed footage stays intact.")
                Picker("Source type", selection: $kind) {
                    ForEach(ProjectSourceKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextField(kind == .camera ? "Camera label, e.g. IPHONE" : "Recorder label, e.g. DJI MIC MINI", text: $label)
                    .textFieldStyle(CRFieldStyle())
                HStack {
                    TextField("Source folder", text: $path)
                        .textFieldStyle(CRFieldStyle())
                    Button("Choose…") {
                        if let url = FolderPicker.chooseFolder(prompt: "Choose the media source folder", startingAt: store.selectedProject?.rootPath ?? "") {
                            path = url.path
                            if label.isEmpty { label = ProjectRecord.inferSourceLabel(url.path, kind: kind) }
                        }
                    }
                    .buttonStyle(CRSecondaryButtonStyle())
                }
                if kind == .camera {
                    Toggle("Index this source now", isOn: $indexNow)
                        .font(CRFont.body(13))
                        .foregroundStyle(cr.text)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(CRSecondaryButtonStyle())
                    Button("Add Source") {
                        Task {
                            await store.addSource(label: label, path: path, kind: kind, indexNow: indexNow)
                            isPresented = false
                        }
                    }
                    .buttonStyle(CRPrimaryButtonStyle())
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || path.isEmpty)
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 640)
    }
}
