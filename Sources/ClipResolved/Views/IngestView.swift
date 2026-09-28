import SwiftUI

struct IngestView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Import Media", subtitle: "Plug in a camera or recorder card. Clip Resolved detects it, scans read-only, and separates likely sessions for you to confirm.")

                if !store.cards.isEmpty {
                    GroupBox("Detected removable media") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.cards, id: \.volumeUUID) { card in
                                HStack {
                                    Image(systemName: "sdcard")
                                    VStack(alignment: .leading) {
                                        Text(card.volumeName).fontWeight(.semibold)
                                        Text(card.mountPath).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if store.sourcePath == card.mountPath, store.scanPayload != nil {
                                        Label("Scanned", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    Button("Rescan") { store.useCard(card) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                GroupBox("Source") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cards scan automatically. Use this only for media already copied to a folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Existing media folder", text: $store.sourcePath)
                            Button("Choose Folder…") {
                                if let url = FolderPicker.chooseFolder(prompt: "Choose an existing media folder", startingAt: store.sourcePath) {
                                    store.sourcePath = url.path
                                }
                            }
                            Button("Scan Folder") { Task { await store.scanSource() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(store.sourcePath.isEmpty || store.isBusy)
                        }
                    }
                }

                if let payload = store.scanPayload {
                    HStack(spacing: 22) {
                        Metric(value: "\(payload.videoCount)", label: "videos")
                        Metric(value: "\(payload.audioCount)", label: "audio files")
                        Metric(value: ByteCountFormatter.string(fromByteCount: payload.totalBytes, countStyle: .file), label: "on source")
                        Metric(value: "\(payload.groups.count)", label: "proposed shoots")
                    }

                    ForEach($store.shootGroups) { $group in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    TextField("Shoot name", text: $group.name)
                                        .font(.title3.weight(.semibold))
                                    Picker("Type", selection: $group.kind) {
                                        ForEach(ProjectKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                                    }
                                    .frame(width: 170)
                                    TextField(group.sourceKind == .audio ? "Recorder" : "Camera", text: $group.sourceLabel)
                                        .frame(width: 170)
                                        .accessibilityLabel(group.sourceKind == .audio ? "Recorder label" : "Camera label")
                                    Label(group.sourceKind.rawValue, systemImage: group.sourceKind == .audio ? "waveform" : "video")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if store.shootGroups.count > 1 {
                                        Menu("Merge") {
                                            ForEach(store.shootGroups.filter { $0.id != group.id && $0.sourceKind == group.sourceKind }) { destination in
                                                Button("Into \(destination.name)") {
                                                    store.mergeShoot(group.id, into: destination.id)
                                                }
                                            }
                                        }
                                    }
                                }
                                Text("\(group.videos.count) videos · \(group.audioFiles.count) audio · \(ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Divider()
                                ForEach(group.files.filter { $0.kind == "video" || $0.kind == "audio" }) { file in
                                    HStack {
                                        Image(systemName: file.kind == "audio" ? "waveform" : (file.width < file.height ? "rectangle.portrait" : "rectangle"))
                                            .foregroundStyle(.secondary)
                                        Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                        Spacer()
                                        Text(file.kind == "audio" ? "Audio" : "\(file.fps, specifier: "%.2f") fps")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        if group.sourceKind == .camera, file.kind == "video" {
                                            Menu("Assign") {
                                            if group.videos.count > 1 {
                                                Button("Split to New Shoot") {
                                                    store.splitIntoNewShoot(file: file, from: group.id)
                                                }
                                                Divider()
                                            }
                                            if store.shootGroups.count > 1 {
                                                ForEach(store.shootGroups.filter { $0.id != group.id && $0.sourceKind == group.sourceKind }) { destination in
                                                    Button("Move to \(destination.name)") {
                                                        store.move(file: file, from: group.id, to: destination.id)
                                                    }
                                                }
                                            }
                                            }
                                            .menuStyle(.borderlessButton)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(group.name, systemImage: "folder")
                        }
                    }

                    GroupBox("Destination") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Add media to", selection: $store.ingestDestinationProjectID) {
                                Text("Create a new project for each confirmed shoot")
                                    .tag(Optional<ProjectRecord.ID>.none)
                                ForEach(store.projects) { project in
                                    Text("Existing project: \(project.name)")
                                        .tag(Optional(project.id))
                                }
                            }
                            if let destinationID = store.ingestDestinationProjectID,
                               let project = store.projects.first(where: { $0.id == destinationID }) {
                                Label(project.rootPath, systemImage: "folder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                HStack {
                                    TextField("Active Projects root", text: $store.activeProjectsRoot)
                                    Button("Choose…") {
                                        if let url = FolderPicker.chooseFolder(prompt: "Choose the Active Projects folder", startingAt: store.activeProjectsRoot) {
                                            store.activeProjectsRoot = url.path
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button(store.ingestDestinationProjectID == nil ? "Confirm Groups and Begin Verified Ingest" : "Verify and Add Media to Project") {
                            Task { await store.confirmAndIngest() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(
                            store.isBusy
                                || store.shootGroups.contains { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                                || (store.ingestDestinationProjectID == nil && store.shootGroups.contains { $0.sourceKind == .audio })
                        )
                        .help(
                            store.ingestDestinationProjectID == nil && store.shootGroups.contains { $0.sourceKind == .audio }
                                ? "Choose an existing project before importing a Mic card."
                                : "Copy, checksum-verify, register, and index these sources."
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: ClipResolvedDesign.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Ingest")
    }
}

private struct Metric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
