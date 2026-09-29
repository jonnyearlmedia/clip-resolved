import AppKit
import SwiftUI

struct IngestView: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore
    @State private var selectedTakeIDs: Set<String> = []
    @State private var expandedShootID: String?

    private var isScanning: Bool {
        store.isBusy && store.scanPayload == nil && !store.sourcePath.isEmpty
    }

    var body: some View {
        Group {
            if isScanning {
                ScanningScreen(store: store)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: ClipResolvedDesign.sectionSpacing) {
                        header
                        if !store.cards.isEmpty { detectedMedia }
                        manualSource
                        if let payload = store.scanPayload {
                            if !payload.scanIssues.isEmpty { scanIssueNotice(payload) }
                            shootSummary(payload)
                            reviewNotice(payload)
                            importSelectionControls
                            shootGrid
                            unassignedRow(payload)
                            destination
                            confirmBar
                        }
                    }
                    .padding(ClipResolvedDesign.pagePadding)
                    .frame(maxWidth: ClipResolvedDesign.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(cr.card)
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.isBusy, store.scanPayload != nil {
                liveIngestProgress
            }
        }
        .sheet(item: $store.completedIngestSummary) { summary in
            IngestCompletionView(store: store, summary: summary)
                .interactiveDismissDisabled(store.isBusy)
        }
    }

    private var liveIngestProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress = parsedIngestProgress(store.progressMessage) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Copying and checksum-verifying")
                            .font(CRFont.heading(15.5))
                            .foregroundStyle(cr.text)
                        Text(progress.project)
                            .font(CRFont.body(14.5))
                            .foregroundStyle(cr.textSecondary)
                    }
                    Spacer(minLength: 16)
                    Text("File \(progress.current) of \(progress.total)")
                        .font(CRFont.mono(14, weight: .semibold))
                        .foregroundStyle(cr.accent)
                }

                ProgressView(value: Double(progress.current), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.linear)
                    .tint(cr.accent)

                Text(progress.filename)
                    .font(CRFont.mono(12.5))
                    .foregroundStyle(cr.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.progressMessage.localizedCaseInsensitiveContains("index") ? "Indexing copied footage" : "Finishing verified ingest")
                            .font(CRFont.heading(15.5))
                            .foregroundStyle(cr.text)
                        Text(store.progressMessage)
                            .font(CRFont.body(14))
                            .foregroundStyle(cr.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: ClipResolvedDesign.contentMaxWidth, alignment: .leading)
        .background(cr.bar, in: RoundedRectangle(cornerRadius: ClipResolvedDesign.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClipResolvedDesign.cornerRadius)
                .strokeBorder(cr.accent.opacity(0.7), lineWidth: 1)
        }
        .padding(.horizontal, ClipResolvedDesign.pagePadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(cr.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verified ingest progress: \(store.progressMessage)")
    }

    private func parsedIngestProgress(_ message: String) -> (project: String, current: Int, total: Int, filename: String)? {
        guard let separator = message.range(of: ": ", options: .backwards) else { return nil }
        let project = String(message[..<separator.lowerBound])
        let remainder = message[separator.upperBound...]
        guard let space = remainder.firstIndex(of: " ") else { return nil }
        let fraction = remainder[..<space].split(separator: "/")
        guard fraction.count == 2,
              let current = Int(fraction[0]),
              let total = Int(fraction[1]) else { return nil }
        let filename = String(remainder[remainder.index(after: space)...])
        return (project, current, total, filename)
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if store.scanPayload == nil {
            PageHeader(
                title: "Import Media",
                subtitle: "Plug in a camera or recorder card. Clip Resolved detects it, scans read-only, and separates likely shoots for you to confirm."
            )
        } else {
            PageHeader(
                title: "\(store.scanPayload?.videoCount ?? 0) video takes · dividing into shoots",
                subtitle: "We found \(store.shootGroups.count) likely \(store.shootGroups.count == 1 ? "shoot" : "shoots") on this source. Name and confirm before ingest."
            )
        }
    }

    // MARK: Detected media

    private var detectedMedia: some View {
        CRSection("Detected removable media") {
            VStack(spacing: 0) {
                ForEach(store.cards, id: \.volumeUUID) { card in
                    HStack(spacing: 12) {
                        CardGlyph()
                            .frame(width: 34, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.volumeName)
                                .font(CRFont.heading(14))
                                .foregroundStyle(cr.text)
                            Text(card.mountPath)
                                .font(CRFont.mono(12))
                                .foregroundStyle(cr.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if store.sourcePath == card.mountPath, store.scanPayload != nil {
                            CRBadge(text: "Scanned ✓", tone: .success)
                        }
                        Button("Rescan") { store.useCard(card) }
                            .buttonStyle(CRSecondaryButtonStyle())
                            .disabled(store.isBusy)
                    }
                    .padding(.vertical, 9)
                    if card.volumeUUID != store.cards.last?.volumeUUID {
                        Rectangle().fill(cr.border).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: Manual source

    private var manualSource: some View {
        CRSection("Source folder") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cards scan automatically. Use this only for media already copied to a folder.")
                    .font(CRFont.body(13.5))
                    .foregroundStyle(cr.textTertiary)
                HStack(spacing: 10) {
                    TextField("Existing media folder", text: $store.sourcePath)
                        .textFieldStyle(CRFieldStyle())
                    Button("Choose…") {
                        if let url = FolderPicker.chooseFolder(prompt: "Choose an existing media folder", startingAt: store.sourcePath) {
                            store.sourcePath = url.path
                        }
                    }
                    .buttonStyle(CRSecondaryButtonStyle())
                    Button("Scan Folder") { Task { await store.scanSource() } }
                        .buttonStyle(CRPrimaryButtonStyle())
                        .disabled(store.sourcePath.isEmpty || store.isBusy)
                }
            }
        }
    }

    // MARK: Summary metrics

    private func scanIssueNotice(_ payload: ScanPayload) -> some View {
        CRCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(cr.danger)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(payload.scanIssues.count) source \(payload.scanIssues.count == 1 ? "file needs" : "files need") attention")
                            .font(CRFont.heading(17))
                            .foregroundStyle(cr.text)
                        Text("Nothing can be confirmed until every source file can be read. Keep the source connected, then try the scan again. Clip Resolved has not copied or changed anything.")
                            .font(CRFont.body(14.5))
                            .foregroundStyle(cr.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button("Try Scan Again") { Task { await store.scanSource() } }
                        .buttonStyle(CRSecondaryButtonStyle())
                        .disabled(store.isBusy)
                }

                ForEach(Array(payload.scanIssues.prefix(4))) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.relativePath)
                            .font(CRFont.mono(13.5, weight: .semibold))
                            .foregroundStyle(cr.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text(issue.reason)
                            .font(CRFont.body(13.5))
                            .foregroundStyle(cr.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if payload.scanIssues.count > 4 {
                    Text("Plus \(payload.scanIssues.count - 4) more unreadable source files.")
                        .font(CRFont.body(13.5))
                        .foregroundStyle(cr.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Source scan blocked by \(payload.scanIssues.count) unreadable files")
    }

    private func shootSummary(_ payload: ScanPayload) -> some View {
        CRCard {
            HStack(spacing: 30) {
                CRMetric(value: "\(payload.videoCount)", label: "videos")
                CRMetric(value: "\(payload.audioCount)", label: "audio files")
                CRMetric(
                    value: ByteCountFormatter.string(fromByteCount: payload.totalBytes, countStyle: .file),
                    label: "on source"
                )
                CRMetric(value: "\(payload.groups.count)", label: "proposed shoots")
                Spacer()
            }
        }
    }

    private func reviewNotice(_ payload: ScanPayload) -> some View {
        CRCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(cr.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review only — nothing copies until you confirm")
                        .font(CRFont.heading(14.5))
                        .foregroundStyle(cr.text)
                    Text("Open one shoot at a time to review its real thumbnails in a bounded strip. Move or split anything that belongs elsewhere; camera WAV sidecars stay attached to their MP4 automatically and remain hidden.")
                        .font(CRFont.body(13.5))
                        .foregroundStyle(cr.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(assignedVideoCount) / \(payload.videoCount) video takes assigned exactly once")
                        .font(CRFont.mono(12))
                        .foregroundStyle(assignedVideoCount == payload.videoCount ? cr.success : cr.danger)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Shoot grid

    private var importSelectionControls: some View {
        CRCard(padding: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    importAllControl
                    Spacer(minLength: 12)
                    importPlanHistoryControls
                }
                VStack(alignment: .leading, spacing: 12) {
                    importAllControl
                    importPlanHistoryControls
                }
            }
        }
    }

    private var importAllControl: some View {
        HStack(spacing: 14) {
            Toggle(
                "Import all shoots",
                isOn: Binding(
                    get: {
                        !store.shootGroups.isEmpty
                            && store.ingestIncludedShootIDs.count == store.shootGroups.count
                    },
                    set: { includeAll in
                        store.ingestIncludedShootIDs = includeAll
                            ? Set(store.shootGroups.map(\.id))
                            : []
                    }
                )
            )
            .toggleStyle(.checkbox)
            .font(CRFont.heading(13.5))
            .accessibilityHint("Turn off to leave every shoot on the card, then select only the shoots you want below")

            Rectangle().fill(cr.border).frame(width: 1, height: 24)

            Text("\(includedShoots.count) of \(store.shootGroups.count) selected · \(ByteCountFormatter.string(fromByteCount: includedBytes, countStyle: .file)) to copy")
                .font(CRFont.mono(12.5))
                .foregroundStyle(cr.textSecondary)

            if !store.ingestIncludedShootIDs.isEmpty {
                Button("Select none") { store.ingestIncludedShootIDs = [] }
                    .buttonStyle(CRLinkButtonStyle())
                    .accessibilityLabel("Leave all shoots on the card")
            }
        }
    }

    private var importPlanHistoryControls: some View {
        HStack(spacing: 8) {
            Button {
                store.undoImportPlanChange()
                reconcileTakeSelection()
            } label: {
                Label("Undo grouping", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(CRSecondaryButtonStyle())
            .disabled(!store.canUndoImportPlan)
            .keyboardShortcut("z", modifiers: .command)

            Button {
                store.redoImportPlanChange()
                reconcileTakeSelection()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .buttonStyle(CRSecondaryButtonStyle())
            .disabled(!store.canRedoImportPlan)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Button {
                store.resetImportPlanToScan()
                selectedTakeIDs = []
                expandedShootID = nil
            } label: {
                Label("Reset groups", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(CRSecondaryButtonStyle())
            .disabled(!store.canResetImportPlan)
            .help("Restore the original scan grouping. Nothing has been copied.")
        }
    }

    private func reconcileTakeSelection() {
        let validIDs = Set(store.shootGroups.flatMap(\.files).map(\.id))
        selectedTakeIDs.formIntersection(validIDs)
        if let expandedShootID, !store.shootGroups.contains(where: { $0.id == expandedShootID }) {
            self.expandedShootID = nil
        }
    }

    private var shootGrid: some View {
        LazyVStack(spacing: 16) {
            ForEach($store.shootGroups) { group in
                let groupID = group.wrappedValue.id
                let index = store.shootGroups.firstIndex { $0.id == groupID } ?? 0
                shootCard(index: index, group: group)
            }
        }
    }

    private func shootCard(index: Int, group: Binding<ShootGroup>) -> some View {
        let shoot = group.wrappedValue
        let isNamed = !shoot.name.trimmingCharacters(in: .whitespaces).isEmpty
        let visibleTakes = shoot.sourceKind == .camera ? shoot.videos : shoot.audioFiles
        let selected = visibleTakes.filter { selectedTakeIDs.contains($0.id) }
        let isExpanded = expandedShootID == shoot.id
        let isIncluded = store.isShootIncluded(shoot.id)

        return CRCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shoot \(index + 1)")
                            .font(CRFont.title(18))
                            .foregroundStyle(cr.text)
                        Text(Self.rangeText(shoot))
                            .font(CRFont.mono(13))
                            .foregroundStyle(cr.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Toggle(
                        "Import this shoot",
                        isOn: Binding(
                            get: { isIncluded },
                            set: { store.setShootIncluded($0, shootID: shoot.id) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .controlSize(.large)
                    .font(CRFont.heading(14.5))
                    .foregroundStyle(isIncluded ? cr.accent : cr.text)
                    .accessibilityLabel(isIncluded ? "Exclude Shoot \(index + 1) from this import" : "Include Shoot \(index + 1) in this import")
                    CRBadge(text: isNamed ? "Named" : "Unnamed", tone: isNamed ? .success : .warm)
                    CRBadge(
                        text: "\(visibleTakes.count) \(visibleTakes.count == 1 ? "take" : "takes")",
                        tone: shoot.sourceKind == .audio ? .warm : .accent
                    )
                }

                shootIdentityControls(group, shoot: shoot)

                if let match = store.recorderProjectMatches[shoot.id] {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: match.isExact ? "checkmark.seal.fill" : "link.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(match.isExact ? cr.success : cr.warm)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(match.isExact ? "Exact camera match: \(match.projectName)" : "Likely camera match: \(match.projectName)")
                                    .font(CRFont.heading(15))
                                    .foregroundStyle(cr.text)
                                CRBadge(text: match.isExact ? "Auto-selected" : "Review match", tone: match.isExact ? .success : .warm)
                            }
                            Text(match.explanation)
                                .font(CRFont.body(13.5))
                                .foregroundStyle(cr.textSecondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((match.isExact ? cr.successSoft : cr.warmSoft), in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder((match.isExact ? cr.success : cr.warm).opacity(0.45))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(match.isExact ? "Exact" : "Likely") camera match: \(match.projectName). \(match.explanation)")
                }

                destinationChooser(for: shoot, shootIndex: index)
                    .disabled(!isIncluded)
                    .opacity(isIncluded ? 1 : 0.55)

                if shoot.sourceKind == .camera, !shoot.audioFiles.isEmpty {
                    Label(
                        "\(shoot.audioFiles.count) camera WAV sidecar\(shoot.audioFiles.count == 1 ? "" : "s") attached and hidden — each follows its MP4 when moved or split",
                        systemImage: "waveform.badge.plus"
                    )
                    .font(CRFont.body(13))
                    .foregroundStyle(cr.textTertiary)
                }

                HStack(alignment: .center, spacing: 12) {
                    compactFilmstrip(Array(visibleTakes.prefix(3)))
                    Spacer(minLength: 8)
                    Button {
                        if isExpanded {
                            expandedShootID = nil
                            selectedTakeIDs.subtract(visibleTakes.map(\.id))
                        } else {
                            expandedShootID = shoot.id
                        }
                    } label: {
                        Label(isExpanded ? "Close take review" : "Review \(visibleTakes.count) takes", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(CRSecondaryButtonStyle())
                    .accessibilityLabel(isExpanded ? "Collapse Shoot \(index + 1) take review" : "Expand Shoot \(index + 1) take review")
                }

                if isExpanded {
                    if !selected.isEmpty {
                        selectedTakeToolbar(selected, in: shoot, shootIndex: index)
                    }

                    ScrollView(.vertical) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 14, alignment: .top)],
                            alignment: .leading,
                            spacing: 14
                        ) {
                            ForEach(visibleTakes) { file in
                                takeCard(file, in: shoot, shootIndex: index)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: visibleTakes.count == 1 ? 430 : 520)
                    .scrollIndicators(.visible)
                    .accessibilityLabel("Scrollable take review for Shoot \(index + 1)")
                }

                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: shoot.totalBytes, countStyle: .file)) \(isIncluded ? "selected to copy" : "will not be copied")")
                    Spacer()
                    Text(isIncluded ? destinationText(for: shoot) : "Stays on card")
                        .lineLimit(1)
                }
                .font(CRFont.mono(13))
                .foregroundStyle(cr.textTertiary)
            }
        }
    }

    private func shootIdentityControls(_ group: Binding<ShootGroup>, shoot: ShootGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shoot / project name")
                        .font(CRFont.heading(13.5))
                        .foregroundStyle(cr.textSecondary)
                    TextField("e.g. Carabao Client Shoot", text: group.name)
                        .textFieldStyle(CRFieldStyle())
                        .accessibilityLabel("Shoot and project name")
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected source")
                        .font(CRFont.heading(13.5))
                        .foregroundStyle(cr.textSecondary)
                    Label(
                        "\(shoot.sourceLabel) · \(shoot.sourceKind == .audio ? "Recorder audio" : "Camera footage")",
                        systemImage: shoot.sourceKind == .audio ? "waveform" : "video.fill"
                    )
                    .font(CRFont.heading(14.5))
                    .foregroundStyle(cr.text)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(cr.bar, in: RoundedRectangle(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(cr.borderStrong) }
                    .accessibilityLabel("Automatically detected source: \(shoot.sourceLabel) \(shoot.sourceKind == .audio ? "recorder" : "camera")")
                }
                .frame(minWidth: 220, maxWidth: 310)
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project type")
                        .font(CRFont.heading(13.5))
                        .foregroundStyle(cr.textSecondary)
                    Picker("Project type", selection: group.kind) {
                        ForEach(ProjectKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                    }
                    .labelsHidden()
                    .frame(minWidth: 150)
                }

                if store.shootGroups.contains(where: { $0.id != shoot.id && $0.sourceKind == shoot.sourceKind }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Combine whole shoot")
                            .font(CRFont.heading(13.5))
                            .foregroundStyle(cr.textSecondary)
                        Menu("Merge into another shoot…") {
                            ForEach(store.shootGroups.filter { $0.id != shoot.id && $0.sourceKind == shoot.sourceKind }) { destination in
                                Button("Shoot \(shootNumber(destination.id)): \(displayName(destination))") {
                                    selectedTakeIDs.subtract(shoot.files.map(\.id))
                                    if expandedShootID == shoot.id { expandedShootID = nil }
                                    store.mergeShoot(shoot.id, into: destination.id)
                                }
                            }
                        }
                        .frame(minWidth: 220)
                        .accessibilityLabel("Merge Shoot \(shootNumber(shoot.id)) into another shoot")
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func compactFilmstrip(_ files: [ScannedFile]) -> some View {
        HStack(spacing: 6) {
            ForEach(files) { file in
                Group {
                    if file.kind == "video" {
                        FootageFrameThumbnailView(path: file.path, seconds: thumbnailTime(file))
                    } else {
                        ZStack {
                            cr.surfaceAlt
                            Image(systemName: "waveform")
                                .foregroundStyle(cr.warm)
                        }
                    }
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .accessibilityHidden(true)
    }

    private func destinationChooser(for shoot: ShootGroup, shootIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Destination for Shoot \(shootIndex + 1)")
                .font(CRFont.heading(13.5))
                .foregroundStyle(cr.textSecondary)

            Menu {
                Button {
                    store.setDestinationProjectID(nil, for: shoot.id)
                } label: {
                    Label(
                        "Create new project: \(displayName(shoot))",
                        systemImage: store.destinationProjectID(for: shoot.id) == nil ? "checkmark" : "folder.badge.plus"
                    )
                }

                if !store.projects.isEmpty {
                    Divider()
                    Section("Add to existing project") {
                        ForEach(store.projects) { project in
                            Button {
                                store.setDestinationProjectID(project.id, for: shoot.id)
                            } label: {
                                Label(
                                    project.name,
                                    systemImage: store.destinationProjectID(for: shoot.id) == project.id ? "checkmark" : "folder"
                                )
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: store.destinationProjectID(for: shoot.id) == nil ? "folder.badge.plus" : "folder.fill.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(cr.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.destinationProjectID(for: shoot.id) == nil ? "CREATE NEW PROJECT" : "ADD TO EXISTING PROJECT")
                            .font(CRFont.mono(12.5, weight: .semibold))
                            .foregroundStyle(cr.textSecondary)
                        Text(destinationText(for: shoot))
                            .font(CRFont.heading(15))
                            .foregroundStyle(cr.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(cr.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(cr.bar, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(cr.borderStrong) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Destination for Shoot \(shootIndex + 1): \(destinationText(for: shoot))")
        }
    }

    private func takeCard(_ file: ScannedFile, in shoot: ShootGroup, shootIndex: Int) -> some View {
        let isSelected = selectedTakeIDs.contains(file.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button { openPreview(file) } label: {
                ZStack {
                    if file.kind == "video" {
                        FootageFrameThumbnailView(path: file.path, seconds: thumbnailTime(file))
                    } else {
                        ZStack {
                            cr.surfaceAlt
                            Image(systemName: "waveform")
                                .font(.system(size: 34))
                                .foregroundStyle(cr.warm)
                        }
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Image(systemName: file.kind == "video" ? "play.circle.fill" : "speaker.wave.2.circle.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.58))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

                    Text(file.duration.editorTimecode)
                        .font(CRFont.mono(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
                        .padding(9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(fileName(file))")
            .help(file.kind == "video" ? "Play this full clip" : "Play this audio file")

            Text(fileName(file))
                .font(CRFont.mono(14, weight: .semibold))
                .foregroundStyle(cr.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(shoot.sourceLabel)
                .font(CRFont.heading(14))
                .foregroundStyle(cr.textSecondary)

            Text(file.relativePath)
                .font(CRFont.mono(12.5))
                .foregroundStyle(cr.textTertiary)
                .lineLimit(2)
                .truncationMode(.middle)

            if file.kind == "video" {
                Text("\(file.width)×\(file.height) · \(String(format: "%.2f", file.fps)) fps")
                    .font(CRFont.mono(12.5))
                    .foregroundStyle(cr.textTertiary)
            }

            Toggle(
                "Select for batch move or split",
                isOn: Binding(
                    get: { isSelected },
                    set: { selected in
                        if selected { selectedTakeIDs.insert(file.id) } else { selectedTakeIDs.remove(file.id) }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .controlSize(.large)
            .font(CRFont.body(14))

            HStack(spacing: 10) {
                Button { openPreview(file) } label: {
                    Label(file.kind == "video" ? "Play Clip" : "Play Audio", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Play \(fileName(file))")

                if store.shootGroups.contains(where: { $0.id != shoot.id && $0.sourceKind == shoot.sourceKind }) {
                    Menu {
                        ForEach(store.shootGroups.filter { $0.id != shoot.id && $0.sourceKind == shoot.sourceKind }) { destination in
                            Button("Shoot \(shootNumber(destination.id)): \(displayName(destination))") {
                                selectedTakeIDs.remove(file.id)
                                store.move(file: file, from: shoot.id, to: destination.id)
                            }
                        }
                    } label: {
                        Label("Move to Shoot…", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .menuStyle(.button)
                    .controlSize(.large)
                    .accessibilityLabel("Move \(fileName(file)) to another shoot")
                }
            }

            Button {
                selectedTakeIDs.remove(file.id)
                store.splitIntoNewShoot(file: file, from: shoot.id)
            } label: {
                Label("Split into New Shoot", systemImage: "rectangle.split.2x1")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled((shoot.sourceKind == .camera ? shoot.videos : shoot.audioFiles).count <= 1)
            .accessibilityLabel("Split \(fileName(file)) into a new shoot")
        }
        .padding(14)
        .background(isSelected ? cr.accentSoft : cr.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? cr.accent : cr.borderStrong, lineWidth: isSelected ? 2 : 1)
        }
    }

    private func openPreview(_ file: ScannedFile) {
        store.previewEvidence = ChatEvidence(
            sourcePath: file.path,
            start: 0,
            end: max(file.duration, 0.1),
            score: 1,
            transcript: nil
        )
    }

    private func selectedTakeToolbar(_ selected: [ScannedFile], in shoot: ShootGroup, shootIndex: Int) -> some View {
        HStack(spacing: 10) {
            CRBadge(text: "\(selected.count) selected", tone: .accent)
            if store.shootGroups.contains(where: { $0.id != shoot.id && $0.sourceKind == shoot.sourceKind }) {
                Menu("Move Selected to Shoot…") {
                    ForEach(store.shootGroups.filter { $0.id != shoot.id && $0.sourceKind == shoot.sourceKind }) { destination in
                        Button("Shoot \(shootNumber(destination.id)): \(displayName(destination))") {
                            selectedTakeIDs.subtract(selected.map(\.id))
                            store.move(files: selected, from: shoot.id, to: destination.id)
                        }
                    }
                }
                .accessibilityLabel("Move \(selected.count) selected takes to another shoot")
            }

            Button("Split Selected into New Shoot") {
                selectedTakeIDs.subtract(selected.map(\.id))
                store.splitIntoNewShoot(files: selected, from: shoot.id)
            }
            .buttonStyle(CRSecondaryButtonStyle())
            .disabled(selected.count >= (shoot.sourceKind == .camera ? shoot.videos.count : shoot.audioFiles.count))

            Spacer()
            Button("Clear Selection") { selectedTakeIDs.subtract(selected.map(\.id)) }
                .buttonStyle(CRLinkButtonStyle())
        }
        .padding(10)
        .background(cr.accentSoft, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Unassigned

    @ViewBuilder private func unassignedRow(_ payload: ScanPayload) -> some View {
        CRCard(padding: 14, dashed: true) {
            HStack {
                Text("Unassigned sidecars")
                    .font(CRFont.body(13.5))
                    .foregroundStyle(cr.textTertiary)
                Spacer()
                Text("\(payload.unassignedSidecars.count) files")
                    .font(CRFont.mono(12.5))
                    .foregroundStyle(payload.unassignedSidecars.isEmpty ? cr.success : cr.warm)
            }
        }
    }

    // MARK: Destination

    private var destination: some View {
        CRSection("Import summary") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Each selected shoot keeps its own destination from the dropdown in that shoot card.")
                    .font(CRFont.heading(13.5))
                    .foregroundStyle(cr.text)

                Text(destinationRollup)
                    .font(CRFont.body(13.5))
                    .foregroundStyle(cr.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                capacitySummary

                if newProjectShootCount > 0 {
                    HStack(spacing: 10) {
                        TextField("Active Projects root", text: $store.activeProjectsRoot)
                            .textFieldStyle(CRFieldStyle())
                        Button("Choose…") {
                            if let url = FolderPicker.chooseFolder(prompt: "Choose the Active Projects folder", startingAt: store.activeProjectsRoot) {
                                store.activeProjectsRoot = url.path
                            }
                        }
                        .buttonStyle(CRSecondaryButtonStyle())
                    }
                    Text("Only the \(newProjectShootCount) selected \(newProjectShootCount == 1 ? "shoot" : "shoots") marked New project will use this folder.")
                        .font(CRFont.body(12.5))
                        .foregroundStyle(cr.textTertiary)
                }
            }
        }
    }

    @ViewBuilder private var capacitySummary: some View {
        if !includedShoots.isEmpty {
            switch Result(catching: { try store.ingestCapacityStatuses() }) {
            case .success(let statuses):
                ForEach(statuses) { status in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: status.hasCapacity ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(status.hasCapacity ? cr.success : cr.danger)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.destinationName)
                                .font(CRFont.heading(14.5))
                                .foregroundStyle(cr.text)
                            Text("Selected \(formattedBytes(status.selectedBytes)) · Need \(formattedBytes(status.requiredBytes)) with verification headroom · \(formattedBytes(status.availableBytes)) available")
                                .font(CRFont.body(13.5))
                                .foregroundStyle(cr.textSecondary)
                            if !status.hasCapacity {
                                Text("Deselect at least \(formattedBytes(status.shortfallBytes)) before importing. Nothing will copy until this fits.")
                                    .font(CRFont.heading(13.5))
                                    .foregroundStyle(cr.danger)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(status.hasCapacity ? cr.successSoft : cr.warmSoft, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(capacityAccessibilityLabel(status))
                }
            case .failure(let error):
                Label("Capacity could not be checked: \(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
                    .font(CRFont.body(13.5))
                    .foregroundStyle(cr.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Confirm

    private var includedShoots: [ShootGroup] {
        store.shootGroups.filter { store.isShootIncluded($0.id) }
    }

    private var includedBytes: Int64 {
        includedShoots.reduce(0) { $0 + $1.totalBytes }
    }

    private var includedNamedCount: Int {
        includedShoots.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private var assignedVideoCount: Int {
        store.shootGroups.reduce(0) { $0 + $1.videos.count }
    }

    private var confirmBar: some View {
        let total = max(includedShoots.count, 1)
        let fraction = Double(includedNamedCount) / Double(total)
        let blockedByAudio = includedShoots.contains {
            $0.sourceKind == .audio && store.destinationProjectID(for: $0.id) == nil
        }
        let missingDestination = includedShoots.contains { shoot in
            guard let projectID = store.destinationProjectID(for: shoot.id) else { return false }
            return !store.projects.contains { $0.id == projectID }
        }
        let allVideosAccountedFor = store.scanPayload.map { assignedVideoCount == $0.videoCount } ?? false
        let hasScanIssues = store.scanPayload?.scanIssues.isEmpty == false
        let capacityReady = includedShoots.isEmpty
            || ((try? store.ingestCapacityStatuses())?.allSatisfy(\.hasCapacity) == true)

        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(includedNamedCount) / \(includedShoots.count) selected shoots ready")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: includedBytes, countStyle: .file))
                }
                .font(CRFont.mono(12))
                .foregroundStyle(cr.textSecondary)
                CRProgressBar(fraction: fraction)
                Text(store.isBusy
                    ? "Copying and checksum-verifying only the selected shoots. Keep both drives connected."
                    : "Nothing has been copied. Confirmation copies only the \(includedShoots.count) selected \(includedShoots.count == 1 ? "shoot" : "shoots"); every source file remains on the card.")
                    .font(CRFont.body(13))
                    .foregroundStyle(cr.textTertiary)
            }

            Button("Confirm \(includedShoots.count) \(includedShoots.count == 1 ? "Shoot" : "Shoots") →") {
                Task { await store.confirmAndIngest() }
            }
            .buttonStyle(CRPrimaryButtonStyle())
            .disabled(
                store.isBusy
                    || includedShoots.isEmpty
                    || includedShoots.contains { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                    || blockedByAudio
                    || missingDestination
                    || !allVideosAccountedFor
                    || hasScanIssues
                    || !capacityReady
            )
            .help(
                blockedByAudio
                    ? "Choose an existing project before importing a recorder card."
                    : !capacityReady
                    ? "The selected shoots do not fit on their destinations. Review the capacity summary."
                    : "Copy, checksum-verify, register, and index these sources."
            )
        }
        .padding(.top, 4)
    }

    // MARK: Helpers

    private static func letter(_ index: Int) -> String {
        guard index < 26 else { return "\(index + 1)" }
        return String(UnicodeScalar(UInt8(65 + index)))
    }

    private func fileName(_ file: ScannedFile) -> String {
        URL(fileURLWithPath: file.path).lastPathComponent
    }

    private func thumbnailTime(_ file: ScannedFile) -> Double {
        min(max(file.duration * 0.25, 0.5), max(0.5, file.duration - 0.25))
    }

    private func shootNumber(_ id: String) -> Int {
        (store.shootGroups.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func displayName(_ shoot: ShootGroup) -> String {
        shoot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed shoot" : shoot.name
    }

    private func destinationText(for shoot: ShootGroup) -> String {
        guard let projectID = store.destinationProjectID(for: shoot.id) else {
            return "New project: \(displayName(shoot))"
        }
        let projectName = store.projects.first { $0.id == projectID }?.name ?? "Missing project"
        return "Existing project: \(projectName)"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func capacityAccessibilityLabel(_ status: OffloadCapacityStatus) -> String {
        if status.hasCapacity {
            return "\(status.destinationName) has enough space. Selected \(formattedBytes(status.selectedBytes)); need \(formattedBytes(status.requiredBytes)) including verification headroom; \(formattedBytes(status.availableBytes)) available."
        }
        return "\(status.destinationName) does not have enough space. Deselect at least \(formattedBytes(status.shortfallBytes)). Nothing will be copied."
    }

    private var newProjectShootCount: Int {
        includedShoots.filter { store.destinationProjectID(for: $0.id) == nil }.count
    }

    private var destinationRollup: String {
        let existingCount = includedShoots.count - newProjectShootCount
        let skippedCount = store.shootGroups.count - includedShoots.count
        return "\(newProjectShootCount) new \(newProjectShootCount == 1 ? "project" : "projects") · \(existingCount) added to existing \(existingCount == 1 ? "project" : "projects") · \(skippedCount) left unselected on the card."
    }

    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlainParser = ISO8601DateFormatter()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static func parse(_ value: String) -> Date? {
        isoParser.date(from: value) ?? isoPlainParser.date(from: value)
    }

    static func rangeText(_ shoot: ShootGroup) -> String {
        guard let start = parse(shoot.start), let end = parse(shoot.end) else {
            return shoot.start.isEmpty ? "Timing unavailable" : "\(shoot.start) → \(shoot.end)"
        }
        let sameDay = Calendar.current.isDate(start, inSameDayAs: end)
        if sameDay {
            return "\(dayFormatter.string(from: start)) · \(clockFormatter.string(from: start))–\(clockFormatter.string(from: end))"
        }
        return "\(dayFormatter.string(from: start)) \(clockFormatter.string(from: start)) → \(dayFormatter.string(from: end)) \(clockFormatter.string(from: end))"
    }
}

private struct IngestCompletionView: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore
    let summary: IngestCompletionSummary
    @State private var showCleanupConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    completionHeader
                    verificationSummary

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Imported shoots")
                            .font(CRFont.title(18))
                            .foregroundStyle(cr.text)
                        ForEach(summary.shoots) { shoot in
                            completedShootRow(shoot)
                        }
                    }

                    verificationChecks

                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(CRFont.body(14))
                            .foregroundStyle(cr.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(28)
            }

            Divider().overlay(cr.border)
            if store.isBusy {
                cleanupProgressPanel
                Divider().overlay(cr.border)
            }
            HStack(spacing: 12) {
                if store.completedCleanupResult == nil {
                    Button("Keep Files on Source") { store.finishCompletedIngest() }
                        .buttonStyle(CRPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)

                    Button("Delete Only Verified Imported Files…", role: .destructive) {
                        showCleanupConfirmation = true
                    }
                    .buttonStyle(CRSecondaryButtonStyle())
                    .disabled(store.isBusy)

                } else {
                    Button("Done") { store.finishCompletedIngest() }
                        .buttonStyle(CRPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(cr.bar)
        }
        .frame(width: 780)
        .frame(minHeight: 620, maxHeight: 760)
        .background(cr.card)
        .confirmationDialog(
            "Delete \(summary.filesVerified) verified imported files from this source?",
            isPresented: $showCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Verified Imported Files", role: .destructive) {
                Task { await store.cleanupCompletedIngest() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Clip Resolved will re-hash every copied destination, verify this is the same source, and then remove only the files listed in this completed import. Any mismatch blocks the entire cleanup before deletion begins.")
        }
    }

    private var cleanupProgressPanel: some View {
        let progress = parsedCleanupProgress(store.progressMessage)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress?.isRemoving == true ? "Removing verified source files" : "Rechecking destination copies")
                        .font(CRFont.heading(16))
                        .foregroundStyle(cr.text)
                    Text(progress?.isRemoving == true
                        ? "Only files from this completed import are being removed. Unchecked shoots are untouched."
                        : "Every copied file must still match its SHA-256 hash before source removal can begin.")
                        .font(CRFont.body(14))
                        .foregroundStyle(cr.textSecondary)
                }
                Spacer(minLength: 16)
                if let progress {
                    Text("File \(progress.current) of \(progress.total)")
                        .font(CRFont.mono(14, weight: .semibold))
                        .foregroundStyle(progress.isRemoving ? cr.warm : cr.accent)
                }
            }

            if let progress {
                ProgressView(value: Double(progress.current), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.linear)
                    .tint(progress.isRemoving ? cr.warm : cr.accent)
                Text(progress.filename)
                    .font(CRFont.mono(12.5))
                    .foregroundStyle(cr.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(cr.accent)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(cr.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source cleanup progress: \(store.progressMessage)")
    }

    private func parsedCleanupProgress(_ message: String) -> (current: Int, total: Int, filename: String, isRemoving: Bool)? {
        let isRemoving = message.hasPrefix("Removing imported source file ")
        let prefix = isRemoving ? "Removing imported source file " : "Rechecking destination file "
        guard message.hasPrefix(prefix) else { return nil }
        let remainder = message.dropFirst(prefix.count)
        guard let colon = remainder.firstIndex(of: ":") else { return nil }
        let countText = remainder[..<colon].split(separator: " ")
        guard countText.count == 3,
              let current = Int(countText[0]),
              countText[1] == "of",
              let total = Int(countText[2]) else { return nil }
        let filenameStart = remainder.index(after: colon)
        return (current, total, remainder[filenameStart...].trimmingCharacters(in: .whitespaces), isRemoving)
    }

    private var completionHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: store.completedCleanupResult == nil ? "checkmark.seal.fill" : "sdcard.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(cr.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.completedCleanupResult == nil ? "Copy verified" : "Source cleanup complete")
                    .font(CRFont.title(26))
                    .foregroundStyle(cr.text)
                Text(completionSubtitle)
                    .font(CRFont.body(15))
                    .foregroundStyle(cr.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var verificationSummary: some View {
        CRCard {
            HStack(spacing: 36) {
                CRMetric(value: "\(summary.filesVerified)", label: "files verified")
                CRMetric(
                    value: ByteCountFormatter.string(fromByteCount: summary.bytesVerified, countStyle: .file),
                    label: "copied"
                )
                CRMetric(value: "\(summary.shoots.count)", label: "shoots imported")
                if let shootsLeftOnSource = summary.shootsLeftOnSource {
                    CRMetric(value: "\(shootsLeftOnSource)", label: "shoots left on card")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func completedShootRow(_ shoot: CompletedIngestShoot) -> some View {
        CRCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shoot.shootName)
                            .font(CRFont.heading(16))
                            .foregroundStyle(cr.text)
                        Text(shoot.addedToExistingProject ? "Added to existing project: \(shoot.projectName)" : "Created new project: \(shoot.projectName)")
                            .font(CRFont.body(14))
                            .foregroundStyle(cr.textSecondary)
                    }
                    Spacer(minLength: 12)
                    CRBadge(text: "SHA-256 verified", tone: .success)
                }

                HStack(spacing: 16) {
                    Label("\(shoot.filesVerified) files", systemImage: "doc.on.doc")
                    Label(ByteCountFormatter.string(fromByteCount: shoot.bytesVerified, countStyle: .file), systemImage: "externaldrive")
                    Label("\(shoot.indexedAssets) clips indexed", systemImage: "sparkles.rectangle.stack")
                    Label(shoot.sourceLabel, systemImage: "video")
                }
                .font(CRFont.body(13.5))
                .foregroundStyle(cr.textSecondary)

                Text(shoot.mediaRoot)
                    .font(CRFont.mono(12.5))
                    .foregroundStyle(cr.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 10) {
                    Button("Open Project Folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: shoot.projectRoot))
                    }
                    .buttonStyle(CRSecondaryButtonStyle())
                    Button("Open Imported Media") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: shoot.mediaRoot))
                    }
                    .buttonStyle(CRSecondaryButtonStyle())
                }
            }
        }
    }

    private var verificationChecks: some View {
        CRCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What Clip Resolved verified")
                    .font(CRFont.heading(16))
                    .foregroundStyle(cr.text)
                completionCheck("Every selected source file copied to its assigned project")
                completionCheck("Every destination file independently re-read with a matching SHA-256 hash")
                completionCheck("Projects registered and footage indexing completed or safely recorded for retry")
                completionCheck(summary.shootsLeftOnSource.map {
                    "\($0) unselected shoots excluded from this import and from cleanup"
                } ?? "Unselected shoots were excluded from this import and from cleanup")
                Text(sourceStateText)
                    .font(CRFont.body(14))
                    .foregroundStyle(store.completedCleanupResult == nil ? cr.textSecondary : cr.success)
                    .padding(.top, 2)
            }
        }
    }

    private var sourceStateText: String {
        if let result = store.completedCleanupResult {
            return "Source cleanup is complete: \(result.filesDeleted) verified imported files were removed. Unselected shoots remain on the card."
        }
        return "Nothing has been erased yet. Source deletion remains a separate, explicit, re-verified action below."
    }

    private func completionCheck(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(CRFont.body(14))
            .foregroundStyle(cr.textSecondary)
            .symbolRenderingMode(.palette)
            .foregroundStyle(cr.success, cr.successSoft)
    }

    private var completionSubtitle: String {
        if let result = store.completedCleanupResult {
            return "Removed \(result.filesDeleted) verified imported files (\(ByteCountFormatter.string(fromByteCount: result.bytesDeleted, countStyle: .file))). Anything you did not select remains on the source."
        }
        return "Every selected file was copied and independently re-read with a matching SHA-256 checksum. Resolve changes still require a separate confirmation."
    }
}

// MARK: - Scanning screen

private struct ScanningScreen: View {
    @Environment(\.cr) private var cr
    let store: AppStore

    var body: some View {
        VStack(spacing: 16) {
            CardGlyph()
                .frame(width: 64, height: 44)

            Text("Removable media detected")
                .crEyebrow()

            Text("Scanning card contents…")
                .font(CRFont.title(22))
                .foregroundStyle(cr.text)

            Text("Reading take timestamps and technical metadata. Nothing is copied or modified yet.")
                .font(CRFont.body(13.5))
                .foregroundStyle(cr.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            IndeterminateBar()
                .frame(width: 280)

            Text(store.progressMessage)
                .font(CRFont.mono(12))
                .foregroundStyle(cr.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct IndeterminateBar: View {
    @Environment(\.cr) private var cr
    @State private var phase: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(cr.surfaceAlt)
                Capsule()
                    .fill(cr.accent)
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: phase * geo.size.width)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    phase = 1.0
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

/// The outlined memory-card mark used on the scan screen and in the detected-media list.
struct CardGlyph: View {
    @Environment(\.cr) private var cr

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(cr.accent, lineWidth: 2)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(cr.accentSoft).frame(height: 2)
                        Capsule().fill(cr.accentSoft).frame(height: 2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                    .frame(width: geo.size.width, alignment: .leading)
                }
        }
    }
}
