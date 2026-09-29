import SwiftUI

struct ProjectMediaOrganizerView: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore
    let project: ProjectRecord
    @Binding var isPresented: Bool

    @State private var files: [ScannedFile] = []
    @State private var selectedPaths: Set<String> = []
    @State private var destinationChoice = "new"
    @State private var newProjectName = "Downtown Shots"
    @State private var newProjectKind: ProjectKind = .personal
    @State private var preview: ChatEvidence?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showMoveConfirmation = false
    @State private var completed: ProjectMediaRelocationResult?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(cr.border)

            if let completed {
                completion(completed)
            } else if isLoading {
                loadingState
            } else if let loadError {
                errorState(loadError)
            } else {
                organizer
                Divider().overlay(cr.border)
                actionBar
            }
        }
        .frame(minWidth: 980, idealWidth: 1120, minHeight: 680, idealHeight: 780)
        .background(cr.card)
        .task { await loadMedia() }
        .confirmationDialog(
            "Move \(selectedVideos.count) selected take\(selectedVideos.count == 1 ? "" : "s")?",
            isPresented: $showMoveConfirmation
        ) {
            Button(moveButtonTitle) { Task { await performMove() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(confirmationText)
        }
        .sheet(item: $preview) { evidence in
            FootagePreviewPresentation(evidence: evidence) { preview = nil }
                .environment(\.cr, cr)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Separate imported shoots")
                    .font(CRFont.display(24))
                    .foregroundStyle(cr.text)
                Text("Review the real clips in \(project.name). Select only the takes that belong elsewhere; attached camera WAVs stay hidden and follow their MP4.")
                    .font(CRFont.body(14))
                    .foregroundStyle(cr.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Close") { isPresented = false }
                .buttonStyle(CRSecondaryButtonStyle())
                .accessibilityLabel("Close imported media organizer")
        }
        .padding(24)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Reading imported clip metadata…")
                .font(CRFont.heading(15))
                .foregroundStyle(cr.text)
            Text("Nothing is moving. Clip Resolved is only preparing thumbnails and capture times.")
                .font(CRFont.body(13.5))
                .foregroundStyle(cr.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(cr.warm)
            Text("Couldn’t read this project’s media")
                .font(CRFont.title(18))
                .foregroundStyle(cr.text)
            Text(message)
                .font(CRFont.body(13.5))
                .foregroundStyle(cr.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await loadMedia() } }
                .buttonStyle(CRPrimaryButtonStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var organizer: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                safetyCallout
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    takeSection(section, index: index)
                }
            }
            .padding(22)
        }
    }

    private var safetyCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "eye.fill")
                .foregroundStyle(cr.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text("Review only — nothing moves until the final confirmation")
                    .font(CRFont.heading(14))
                    .foregroundStyle(cr.text)
                Text("A 20-minute-or-longer recording break is shown as a possible shoot boundary. It is only a visual hint; you decide clip by clip.")
                    .font(CRFont.body(13))
                    .foregroundStyle(cr.textSecondary)
            }
        }
        .padding(14)
        .background(cr.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }

    private func takeSection(_ section: [ScannedFile], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recording block \(index + 1)")
                        .font(CRFont.title(17))
                        .foregroundStyle(cr.text)
                    Text(sectionRange(section))
                        .font(CRFont.body(13))
                        .foregroundStyle(cr.textSecondary)
                }
                Spacer()
                Button(section.allSatisfy { selectedPaths.contains($0.path) } ? "Clear Block" : "Select Block") {
                    let paths = Set(section.map(\.path))
                    if paths.isSubset(of: selectedPaths) {
                        selectedPaths.subtract(paths)
                    } else {
                        selectedPaths.formUnion(paths)
                    }
                }
                .buttonStyle(CRSecondaryButtonStyle())
                .accessibilityLabel("Select all \(section.count) takes in recording block \(index + 1)")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 270), spacing: 12)], spacing: 12) {
                ForEach(section) { file in
                    takeCard(file)
                }
            }
        }
    }

    private func takeCard(_ file: ScannedFile) -> some View {
        let selected = selectedPaths.contains(file.path)
        return VStack(alignment: .leading, spacing: 9) {
            Button {
                preview = ChatEvidence(sourcePath: file.path, start: 0, end: max(0.1, file.duration), score: 1, transcript: nil)
            } label: {
                ZStack {
                    FootageFrameThumbnailView(path: file.path, seconds: thumbnailTime(file))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.56))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    Text(file.duration.editorTimecode)
                        .font(CRFont.mono(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
                        .padding(7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(fileName(file))")

            Toggle(isOn: Binding(
                get: { selectedPaths.contains(file.path) },
                set: { checked in
                    if checked { selectedPaths.insert(file.path) } else { selectedPaths.remove(file.path) }
                }
            )) {
                Text(fileName(file))
                    .font(CRFont.mono(13, weight: .semibold))
                    .foregroundStyle(cr.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .toggleStyle(.checkbox)
            .controlSize(.large)

            HStack(spacing: 8) {
                Text(captureTime(file))
                if attachedCount(file) > 0 {
                    Label("WAV attached", systemImage: "waveform")
                }
            }
            .font(CRFont.body(12.5))
            .foregroundStyle(cr.textSecondary)
        }
        .padding(11)
        .background(selected ? cr.accentSoft : cr.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(selected ? cr.accent : cr.borderStrong, lineWidth: selected ? 2 : 1)
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isBusy {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(store.progressMessage)
                            .font(CRFont.heading(13.5))
                            .foregroundStyle(cr.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text("The app is moving the selected media, preserving its search index, and leaving every unselected take in \(project.name).")
                        .font(CRFont.body(12.5))
                        .foregroundStyle(cr.textSecondary)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { destinationControls; moveAction }
                    VStack(alignment: .leading, spacing: 12) { destinationControls; moveAction }
                }
            }
            if let error = store.errorMessage {
                Text(error)
                    .font(CRFont.body(13))
                    .foregroundStyle(cr.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(cr.bar)
    }

    @ViewBuilder private var destinationControls: some View {
        Picker("Move selected takes to", selection: $destinationChoice) {
            Text("New project").tag("new")
            ForEach(store.projects.filter { $0.id != project.id }) { destination in
                Text("Existing: \(destination.name)").tag(destination.id.uuidString)
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 210)

        if destinationChoice == "new" {
            TextField("New project name", text: $newProjectName)
                .textFieldStyle(CRFieldStyle())
                .frame(minWidth: 210, maxWidth: 300)
            Picker("Project type", selection: $newProjectKind) {
                ForEach(ProjectKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
    }

    private var moveAction: some View {
        HStack(spacing: 12) {
            Spacer()
            Text("\(selectedVideos.count) of \(videos.count) selected")
                .font(CRFont.mono(12.5))
                .foregroundStyle(cr.textSecondary)
            Button("Review Move →") { showMoveConfirmation = true }
                .buttonStyle(CRPrimaryButtonStyle())
                .disabled(selectedVideos.isEmpty || (destinationChoice == "new" && newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
    }

    private func completion(_ result: ProjectMediaRelocationResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Project corrected", systemImage: "checkmark.circle.fill")
                .font(CRFont.display(24))
                .foregroundStyle(cr.success)
            Text("Moved \(result.takesMoved) video take\(result.takesMoved == 1 ? "" : "s") and \(result.filesMoved - result.takesMoved) attached file\(result.filesMoved - result.takesMoved == 1 ? "" : "s"). Unselected takes stayed in \(project.name), and the existing search intelligence moved with the clips.")
                .font(CRFont.body(14))
                .foregroundStyle(cr.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Open Destination Project") { isPresented = false }
                    .buttonStyle(CRPrimaryButtonStyle())
                Button("Reveal Moved Media") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: result.sources.first?.path ?? result.destinationProjectRoot))
                }
                .buttonStyle(CRSecondaryButtonStyle())
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var videos: [ScannedFile] { files.filter { $0.kind == "video" } }
    private var selectedVideos: [ScannedFile] { videos.filter { selectedPaths.contains($0.path) } }

    private var sections: [[ScannedFile]] {
        var result: [[ScannedFile]] = []
        var previous: ScannedFile?
        for file in videos {
            if let previous,
               let previousDate = parseDate(previous.captureTime),
               let date = parseDate(file.captureTime),
               date.timeIntervalSince(previousDate.addingTimeInterval(previous.duration)) >= 20 * 60 {
                result.append([])
            } else if result.isEmpty {
                result.append([])
            }
            result[result.count - 1].append(file)
            previous = file
        }
        return result
    }

    private var selectedDestinationID: UUID? {
        destinationChoice == "new" ? nil : UUID(uuidString: destinationChoice)
    }

    private var destinationName: String {
        if let id = selectedDestinationID, let destination = store.projects.first(where: { $0.id == id }) {
            return destination.name
        }
        return newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var moveButtonTitle: String { "Move into \(destinationName)" }

    private var confirmationText: String {
        let sidecars = Set(selectedVideos.map(\.groupKey)).reduce(0) { count, key in
            count + files.filter { $0.kind != "video" && $0.groupKey == key }.count
        }
        return "Moves only these \(selectedVideos.count) MP4 take\(selectedVideos.count == 1 ? "" : "s") and \(sidecars) attached sidecar\(sidecars == 1 ? "" : "s") from \(project.name) into \(destinationName). Search, Project Chat, and later Resolve actions will use the corrected projects. Nothing on the camera card is touched."
    }

    private func loadMedia() async {
        isLoading = true
        loadError = nil
        do {
            files = try await store.importedMediaFiles(for: project)
            if videos.isEmpty { loadError = "No imported camera clips were found in the registered sources." }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func performMove() async {
        completed = await store.relocateImportedTakes(
            videoPaths: selectedVideos.map(\.path),
            from: project.id,
            to: selectedDestinationID,
            newProjectName: newProjectName,
            newProjectKind: newProjectKind
        )
    }

    private func attachedCount(_ file: ScannedFile) -> Int {
        files.filter { $0.kind != "video" && $0.groupKey == file.groupKey }.count
    }

    private func fileName(_ file: ScannedFile) -> String { URL(fileURLWithPath: file.path).lastPathComponent }
    private func thumbnailTime(_ file: ScannedFile) -> Double { min(max(file.duration * 0.25, 0.5), max(0.5, file.duration - 0.25)) }

    private func captureTime(_ file: ScannedFile) -> String {
        guard let date = parseDate(file.captureTime) else { return "Capture time unavailable" }
        return Self.timeFormatter.string(from: date)
    }

    private func sectionRange(_ files: [ScannedFile]) -> String {
        guard let first = files.first, let last = files.last,
              let start = parseDate(first.captureTime), let end = parseDate(last.captureTime) else {
            return "\(files.count) takes"
        }
        return "\(Self.dayFormatter.string(from: start)) · \(Self.timeFormatter.string(from: start))–\(Self.timeFormatter.string(from: end)) · \(files.count) takes"
    }

    private func parseDate(_ value: String) -> Date? { Self.isoFractional.date(from: value) ?? Self.iso.date(from: value) }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
