import SwiftUI

struct IngestView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ingest camera media")
                        .font(.largeTitle.bold())
                    Text("Scan read-only, confirm every shoot, then copy and checksum-verify before analysis.")
                        .foregroundStyle(.secondary)
                }

                if !store.cards.isEmpty {
                    GroupBox("Detected camera media") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.cards, id: \.volumeUUID) { card in
                                HStack {
                                    Image(systemName: "sdcard")
                                    VStack(alignment: .leading) {
                                        Text(card.volumeName).fontWeight(.semibold)
                                        Text(card.mountPath).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Use Card") { store.useCard(card) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                GroupBox("Source") {
                    HStack {
                        TextField("Camera card or existing footage folder", text: $store.sourcePath)
                        Button("Choose…") {
                            if let url = FolderPicker.chooseFolder(prompt: "Choose an Osmo card or footage folder", startingAt: store.sourcePath) {
                                store.sourcePath = url.path
                            }
                        }
                        Button("Scan") { Task { await store.scanSource() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.sourcePath.isEmpty || store.isBusy)
                    }
                }

                if let payload = store.scanPayload {
                    HStack(spacing: 22) {
                        Metric(value: "\(payload.videoCount)", label: "videos")
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
                                    if store.shootGroups.count > 1 {
                                        Menu("Merge") {
                                            ForEach(store.shootGroups.filter { $0.id != group.id }) { destination in
                                                Button("Into \(destination.name)") {
                                                    store.mergeShoot(group.id, into: destination.id)
                                                }
                                            }
                                        }
                                    }
                                }
                                Text("\(group.videos.count) videos · \(ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Divider()
                                ForEach(group.videos) { file in
                                    HStack {
                                        Image(systemName: file.width < file.height ? "rectangle.portrait" : "rectangle")
                                            .foregroundStyle(.secondary)
                                        Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                        Spacer()
                                        Text("\(file.fps, specifier: "%.2f") fps")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Menu("Assign") {
                                            if group.videos.count > 1 {
                                                Button("Split to New Shoot") {
                                                    store.splitIntoNewShoot(file: file, from: group.id)
                                                }
                                                Divider()
                                            }
                                            if store.shootGroups.count > 1 {
                                                ForEach(store.shootGroups.filter { $0.id != group.id }) { destination in
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
                        } label: {
                            Label(group.name, systemImage: "folder")
                        }
                    }

                    GroupBox("Destination") {
                        HStack {
                            TextField("Active Projects root", text: $store.activeProjectsRoot)
                            Button("Choose…") {
                                if let url = FolderPicker.chooseFolder(prompt: "Choose the Active Projects folder", startingAt: store.activeProjectsRoot) {
                                    store.activeProjectsRoot = url.path
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Confirm Groups and Begin Verified Ingest") {
                            Task { await store.confirmAndIngest() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(store.isBusy || store.shootGroups.contains { $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
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
