import SwiftUI

struct ChatView: View {
    @Bindable var store: AppStore
    @State private var draft = ""
    @State private var showMemory = false
    @State private var previewEvidence: ChatEvidence?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.selectedProject == nil {
                ContentUnavailableView(
                    "Open a project first",
                    systemImage: "folder.badge.plus",
                    description: Text("Add an existing project from Footage Search, then chat with its indexed footage here.")
                )
            } else {
                conversation
                Divider()
                composer
            }
        }
        .navigationTitle("Project Chat")
        .sheet(isPresented: $showMemory) {
            MemoryView(store: store, isPresented: $showMemory)
        }
        .sheet(item: $previewEvidence) { evidence in
            FootagePreviewView(evidence: evidence)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Project", selection: $store.selectedProjectID) {
                ForEach(store.projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .frame(maxWidth: 320)

            Label(store.claudeStatus, systemImage: store.claudeStatus.contains("connected") ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(store.claudeStatus.contains("connected") ? .green : .secondary)

            Spacer()

            Button {
                showMemory = true
            } label: {
                Label("Memory", systemImage: "brain.head.profile")
            }

            Menu {
                Button("Clear This Conversation", role: .destructive) {
                    store.clearSelectedProjectChat()
                }
                .disabled(store.selectedProjectMessages.isEmpty)
                Button("Recheck Claude") {
                    Task { await store.refreshClaudeStatus() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(16)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if store.selectedProjectMessages.isEmpty {
                        welcome
                    } else {
                        ForEach(store.selectedProjectMessages) { message in
                            ChatMessageView(
                                message: message,
                                preview: { evidence in previewEvidence = evidence },
                                stageAction: { action in
                                    store.stageSuggestedChatAction(action, projectID: message.projectID)
                                }
                            )
                                .id(message.id)
                        }
                    }

                    if store.isChatBusy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Working with the local project tools…")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                    }

                    if let action = store.pendingChatAction,
                       action.projectID == store.selectedProject?.id {
                        PendingActionView(store: store, action: action)
                    }
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: store.chatMessages.count) { _, _ in
                guard let last = store.selectedProjectMessages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Chat with \(store.selectedProject?.name ?? "this project")")
                .font(.title2.bold())
            Text("Ask what is in the footage, search for new visual or spoken moments, or request a source-linked SELECTS timeline. New wording uses the existing index.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)

            HStack(spacing: 10) {
                suggestion("What footage is indexed?")
                suggestion("Find food shots")
                suggestion("Make a FOOD SHOTS SELECTS timeline")
            }

            Text("Footage analysis stays local. Claude receives project status, saved preferences, conversation text, and returned timestamp evidence, not your MP4 files.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 650)
        }
        .padding(.vertical, 80)
    }

    private func suggestion(_ text: String) -> some View {
        Button(text) {
            draft = text
            send()
        }
        .buttonStyle(.bordered)
        .disabled(store.isChatBusy || store.isBusy)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about footage, preferences, or a Resolve SELECTS timeline…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit { send() }

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [])
            }

            Text("Resolve changes always require confirmation. Originals are never rewritten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var canSend: Bool {
        store.selectedProject != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isChatBusy
            && !store.isBusy
    }

    private func send() {
        guard canSend else { return }
        let message = draft
        draft = ""
        Task { await store.sendChat(message) }
    }
}

private struct ChatMessageView: View {
    let message: ChatMessage
    let preview: (ChatEvidence) -> Void
    let stageAction: (ChatSuggestedAction) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 110) }

            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .textSelection(.enabled)

                if !message.evidence.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(message.evidence) { evidence in
                            Button {
                                preview(evidence)
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    EvidenceThumbnailView(evidence: evidence)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(evidence.fileName)
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                        Text("\(evidence.start.editorTimecode) – \(evidence.end.editorTimecode)")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(evidence.score, format: .number.precision(.fractionLength(3)))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.tint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(evidence.sourcePath)

                            if let transcript = evidence.transcript, !transcript.isEmpty {
                                Text(transcript)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                }

                if let action = message.suggestedAction {
                    Button {
                        stageAction(action)
                    } label: {
                        Label("Create \(action.timelineName) in Resolve", systemImage: "timeline.selection")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                message.role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .frame(maxWidth: 700, alignment: .leading)

            if message.role == .assistant { Spacer(minLength: 110) }
        }
    }
}

private struct PendingActionView: View {
    let store: AppStore
    let action: PendingChatAction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(action.title, systemImage: "checkmark.shield")
                .font(.headline)
            switch action.kind {
            case .createSelects:
                Text("This will append \(action.rangeCount) handled ranges to the main SELECTS and create a NOT SELECTED timeline containing the exact source-frame remainder. No new video files will be rendered.")
                    .foregroundStyle(.secondary)
            case .createSmartSelects:
                Text("This creates 00 ALL RAW FOOTAGE STRINGOUT, seven professionally named restaurant category timelines, and one ALL FOOTAGE NOT SELECTED REVIEW timeline. Every item references the original indexed MP4s.")
                    .foregroundStyle(.secondary)
            case .prepareResolve:
                Text("This will connect to the open saved Resolve project, import originals, and create the required bins.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { store.cancelPendingChatAction() }
                Button(confirmButtonTitle) {
                    Task { await store.confirmPendingChatAction() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.35)))
        .frame(maxWidth: 700)
    }

    private var confirmButtonTitle: String {
        switch action.kind {
        case .createSelects: "Create SELECTS in Resolve"
        case .createSmartSelects: "Create Complete Package"
        case .prepareResolve: "Prepare Resolve Project"
        }
    }
}

private struct MemoryView: View {
    @Bindable var store: AppStore
    @Binding var isPresented: Bool
    @State private var scope: ChatMemoryScope = .project
    @State private var category = "Editing preference"
    @State private var content = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Memory").font(.title2.bold())
                    Text("These details are saved locally and included when you chat with the relevant project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            List {
                Section("Remember something") {
                    Picker("Use in", selection: $scope) {
                        ForEach(ChatMemoryScope.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    TextField("Category", text: $category)
                    TextField("Preference or project fact", text: $content, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Spacer()
                        Button("Add Memory") {
                            store.addMemory(scope: scope, category: category, content: content)
                            content = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Saved for all projects") {
                    memoryRows(store.chatMemories.filter { $0.scope == .global })
                }

                Section("Saved for \(store.selectedProject?.name ?? "this project")") {
                    memoryRows(store.chatMemories.filter {
                        $0.scope == .project && $0.projectID == store.selectedProject?.id
                    })

                    if store.chatMemories.contains(where: {
                        $0.scope == .project && $0.projectID == store.selectedProject?.id
                    }) {
                        Button("Clear This Project's Memory", role: .destructive) {
                            store.clearSelectedProjectMemory()
                        }
                    }
                }
            }
        }
        .frame(width: 680, height: 620)
    }

    @ViewBuilder
    private func memoryRows(_ items: [ChatMemoryItem]) -> some View {
        if items.isEmpty {
            Text("Nothing saved yet")
                .foregroundStyle(.secondary)
        } else {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.category).font(.caption).foregroundStyle(.secondary)
                        Text(item.content).textSelection(.enabled)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteMemory(item.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Forget this detail")
                }
            }
        }
    }
}
