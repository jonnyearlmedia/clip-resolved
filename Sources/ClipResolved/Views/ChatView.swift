import SwiftUI

struct ChatView: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore
    @State private var draft = ""
    @State private var showMemory = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.selectedProject == nil {
                CREmptyState(
                    title: "Open a project first",
                    message: "Add an existing project from Footage Search, then chat with its indexed footage here.",
                    symbol: "folder.badge.plus"
                )
            } else {
                conversation
                composer
            }
        }
        .background(cr.card)
        .sheet(isPresented: $showMemory) {
            MemoryView(store: store, isPresented: $showMemory)
                .environment(\.cr, cr)
        }
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { headerProject; Spacer(); headerActions }
            VStack(alignment: .leading, spacing: 10) {
                headerProject
                HStack { Spacer(); headerActions }
            }
        }
        .padding(.horizontal, ClipResolvedDesign.pagePadding)
        .padding(.vertical, 14)
        .background(cr.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(cr.border).frame(height: 1) }
    }

    private var isClaudeConnected: Bool { store.claudeStatus.contains("connected") }

    private var headerProject: some View {
        HStack(spacing: 12) {
            ProjectPicker(store: store)
            HStack(spacing: 6) {
                Circle()
                    .fill(isClaudeConnected ? cr.success : cr.warm)
                    .frame(width: 6, height: 6)
                Text(store.claudeStatus)
                    .font(CRFont.mono(11))
                    .foregroundStyle(isClaudeConnected ? cr.success : cr.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button("Memory") { showMemory = true }
                .buttonStyle(CRSecondaryButtonStyle())
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
                    .foregroundStyle(cr.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Conversation options")
            .help("Conversation options")
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if store.selectedProjectMessages.isEmpty {
                        welcome
                    } else {
                        ForEach(store.selectedProjectMessages) { message in
                            ChatMessageView(
                                message: message,
                                preview: { evidence in store.previewEvidence = evidence },
                                stageAction: { action in
                                    Task {
                                        await store.stageSuggestedChatAction(action, projectID: message.projectID)
                                    }
                                }
                            )
                            .id(message.id)
                        }
                    }

                    if store.isChatBusy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Working with the local project tools…")
                                .font(CRFont.mono(11.5))
                                .foregroundStyle(cr.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }

                    if let action = store.pendingChatAction,
                       action.projectID == store.selectedProject?.id {
                        PendingActionView(store: store, action: action)
                            .id("pending-chat-action")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(ClipResolvedDesign.pagePadding)
                .frame(maxWidth: 1_120)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: store.chatMessages.count) { _, _ in
                guard let last = store.selectedProjectMessages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: store.pendingChatAction?.id) { _, actionID in
                guard actionID != nil else { return }
                withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Text("Ask this project anything")
                .crEyebrow()

            Text("Chat with \(store.selectedProject?.name ?? "this project")")
                .font(CRFont.title(22))
                .foregroundStyle(cr.text)

            Text("Ask what is in the footage, search for new visual or spoken moments, or request a source-linked SELECTS timeline. New wording uses the existing index.")
                .font(CRFont.body(13.5))
                .foregroundStyle(cr.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    suggestion("What footage is indexed?")
                    suggestion("Find food shots")
                    suggestion("Make a FOOD SHOTS SELECTS timeline")
                }
                VStack(spacing: 8) {
                    suggestion("What footage is indexed?")
                    suggestion("Find food shots")
                    suggestion("Make a FOOD SHOTS SELECTS timeline")
                }
            }

            Text("Media analysis stays local. Claude receives project status, saved preferences, transcript text, conversation text, and returned timestamp evidence — never your MP4 or WAV files.")
                .font(CRFont.body(11))
                .foregroundStyle(cr.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
        }
        .padding(.vertical, 60)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            draft = text
            send()
        } label: {
            CRChip(text: text)
        }
        .buttonStyle(.plain)
        .disabled(store.isChatBusy || store.isBusy)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about footage, preferences, or a Resolve SELECTS timeline…", text: $draft, axis: .vertical)
                    .textFieldStyle(CRFieldStyle())
                    .lineLimit(1...5)
                    .onSubmit { send() }

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(cr.accentOn)
                        .frame(width: 44, height: 44)
                        .background(canSend ? cr.accent : cr.surfaceAlt, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel("Send message")
                .help("Send message")
            }

            Text("Resolve changes always require confirmation. Originals are never rewritten.")
                .font(CRFont.body(11))
                .foregroundStyle(cr.textTertiary)
        }
        .padding(.horizontal, ClipResolvedDesign.pagePadding)
        .padding(.vertical, 14)
        .background(cr.bar)
        .overlay(alignment: .top) { Rectangle().fill(cr.border).frame(height: 1) }
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

// MARK: - Message bubble

private struct ChatMessageView: View {
    @Environment(\.cr) private var cr
    let message: ChatMessage
    let preview: (ChatEvidence) -> Void
    let stageAction: (ChatSuggestedAction) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 110) }

            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(CRFont.body(13.5))
                    .foregroundStyle(cr.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.evidence.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(message.evidence) { evidence in
                            evidenceRow(evidence)
                        }
                    }
                }

                if let action = message.suggestedAction {
                    Button("Use \(action.timelineName) in Resolve →") {
                        stageAction(action)
                    }
                    .buttonStyle(CRPrimaryButtonStyle())
                }

                Text(message.createdAt, style: .time)
                    .font(CRFont.mono(10))
                    .foregroundStyle(cr.textTertiary)
            }
            .padding(18)
            .background(
                message.role == .user ? cr.accentSoft : cr.surface,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(message.role == .user ? cr.accentSoft : cr.border)
            }
            .frame(maxWidth: 860, alignment: .leading)

            if message.role == .assistant { Spacer(minLength: 110) }
        }
    }

    private func evidenceRow(_ evidence: ChatEvidence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                preview(evidence)
            } label: {
                HStack(spacing: 10) {
                    EvidenceThumbnailView(evidence: evidence)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(evidence.fileName)
                            .font(CRFont.mono(11.5))
                            .foregroundStyle(cr.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(evidence.start.editorTimecode) – \(evidence.end.editorTimecode)")
                            .font(CRFont.mono(11))
                            .foregroundStyle(cr.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(cr.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(evidence.sourcePath)

            if let transcript = evidence.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(CRFont.body(11.5))
                    .foregroundStyle(cr.textTertiary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(cr.bar, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(cr.border) }
    }
}

// MARK: - Pending action

private struct PendingActionView: View {
    @Environment(\.cr) private var cr
    let store: AppStore
    let action: PendingChatAction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(cr.warm)
                Text(action.title)
                    .font(CRFont.heading(14))
                    .foregroundStyle(cr.text)
            }

            Text(explanation)
                .font(CRFont.body(13))
                .foregroundStyle(cr.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Cancel") { store.cancelPendingChatAction() }
                    .buttonStyle(CRSecondaryButtonStyle())
                Button(confirmButtonTitle) {
                    Task { await store.confirmPendingChatAction() }
                }
                .buttonStyle(CRPrimaryButtonStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: 860, alignment: .leading)
        .background(cr.warmSoft, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(cr.warm.opacity(0.35)) }
    }

    private var explanation: String {
        switch action.kind {
        case .transcribeAudio:
            "Clip Resolved will create local timed transcripts from the dedicated recorder source. It reads the copied audio in place, does not alter the recordings, and does not change Resolve."
        case .createSelects:
            "Clip Resolved will open DaVinci Resolve if needed, create or load this project, import its original media, append \(action.rangeCount) handled ranges to the main SELECTS, and create a NOT SELECTED timeline containing the exact source-frame remainder. No new video files will be rendered."
        case .createExactRanges:
            "Clip Resolved will create a source-linked timeline from the \(action.rangeCount) exact transcript range\(action.rangeCount == 1 ? "" : "s") listed above, plus a NOT SELECTED timeline for the remaining material in those same source files. No media will be rendered or rewritten."
        case .createSmartSelects:
            "This creates a chronological 00 ALL RAW FOOTAGE STRINGOUT, one merged ALL B-ROLL SELECTS timeline, the project’s professionally named category timelines, and one ALL FOOTAGE NOT SELECTED REVIEW timeline. Every item references the original indexed media."
        case .openTimeline:
            "This timeline already exists in the open Resolve project. Clip Resolved will switch to it without creating a duplicate or changing its contents."
        case .prepareResolve:
            "Clip Resolved will open DaVinci Resolve if needed, create or load this saved project, import originals, and create the required bins."
        }
    }

    private var confirmButtonTitle: String {
        switch action.kind {
        case .transcribeAudio: "Transcribe Spoken Audio"
        case .createSelects: "Create SELECTS in Resolve"
        case .createExactRanges: "Create Exact Ranges in Resolve"
        case .createSmartSelects: "Create Complete Package"
        case .openTimeline: "Open Existing Timeline"
        case .prepareResolve: "Prepare Resolve Project"
        }
    }
}

// MARK: - Memory

private struct MemoryView: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore
    @Binding var isPresented: Bool
    @State private var scope: ChatMemoryScope = .project
    @State private var category = "Editing preference"
    @State private var content = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Memory")
                        .font(CRFont.title(20))
                        .foregroundStyle(cr.text)
                    Text("These details are saved locally and included when you chat with the relevant project.")
                        .font(CRFont.body(11.5))
                        .foregroundStyle(cr.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(CRPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            .background(cr.bar)
            .overlay(alignment: .bottom) { Rectangle().fill(cr.border).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CRSection("Remember something") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Use in", selection: $scope) {
                                ForEach(ChatMemoryScope.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            TextField("Category", text: $category)
                                .textFieldStyle(CRFieldStyle())
                            TextField("Preference or project fact", text: $content, axis: .vertical)
                                .textFieldStyle(CRFieldStyle())
                                .lineLimit(2...4)
                            HStack {
                                Spacer()
                                Button("Add Memory") {
                                    store.addMemory(scope: scope, category: category, content: content)
                                    content = ""
                                }
                                .buttonStyle(CRPrimaryButtonStyle())
                                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    CRSection("Saved for all projects") {
                        memoryRows(store.chatMemories.filter { $0.scope == .global })
                    }

                    CRSection("Saved for \(store.selectedProject?.name ?? "this project")") {
                        VStack(alignment: .leading, spacing: 10) {
                            memoryRows(store.chatMemories.filter {
                                $0.scope == .project && $0.projectID == store.selectedProject?.id
                            })

                            if store.chatMemories.contains(where: {
                                $0.scope == .project && $0.projectID == store.selectedProject?.id
                            }) {
                                Button("Clear This Project's Memory") {
                                    store.clearSelectedProjectMemory()
                                }
                                .buttonStyle(CRSecondaryButtonStyle())
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(cr.card)
        }
        .frame(width: 680, height: 620)
        .background(cr.card)
    }

    @ViewBuilder
    private func memoryRows(_ items: [ChatMemoryItem]) -> some View {
        if items.isEmpty {
            Text("Nothing saved yet")
                .font(CRFont.body(12.5))
                .foregroundStyle(cr.textTertiary)
        } else {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.category)
                                .crEyebrow(size: 10)
                            Text(item.content)
                                .font(CRFont.body(12.5))
                                .foregroundStyle(cr.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button {
                            store.deleteMemory(item.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(cr.danger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Forget \(item.category)")
                        .help("Forget this detail")
                    }
                    .padding(.vertical, 8)
                    if item.id != items.last?.id {
                        Rectangle().fill(cr.border).frame(height: 1)
                    }
                }
            }
        }
    }
}
