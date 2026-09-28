import Foundation

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case ingest = "Ingest"
    case chat = "Project Chat"
    case search = "Footage Search"
    case activity = "Activity"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .ingest: "externaldrive.badge.plus"
        case .chat: "bubble.left.and.bubble.right"
        case .search: "sparkle.magnifyingglass"
        case .activity: "list.bullet.rectangle"
        }
    }
}

enum ProjectKind: String, Codable, CaseIterable, Identifiable {
    case personal = "Personal"
    case client = "Client"
    var id: String { rawValue }
}

enum SearchMode: String, Codable, CaseIterable, Identifiable {
    case visual = "Visual"
    case spoken = "Spoken words"
    var id: String { rawValue }
}

struct ScannedFile: Codable, Hashable, Identifiable {
    let path: String
    let relativePath: String
    let groupKey: String
    let kind: String
    let size: Int64
    let captureTime: String
    let duration: Double
    let fps: Double
    let width: Int
    let height: Int
    let hasAudio: Bool

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path, kind, size, duration, fps, width, height
        case relativePath = "relative_path"
        case groupKey = "group_key"
        case captureTime = "capture_time"
        case hasAudio = "has_audio"
    }
}

struct ScannedGroupPayload: Codable {
    let id: String
    let suggestedName: String
    let start: String
    let end: String
    let videoCount: Int
    let fileCount: Int
    let totalBytes: Int64
    let files: [ScannedFile]

    enum CodingKeys: String, CodingKey {
        case id, start, end, files
        case suggestedName = "suggested_name"
        case videoCount = "video_count"
        case fileCount = "file_count"
        case totalBytes = "total_bytes"
    }
}

struct ScanPayload: Codable {
    let source: String
    let videoCount: Int
    let sidecarCount: Int
    let totalBytes: Int64
    let groups: [ScannedGroupPayload]
    let unassignedSidecars: [ScannedFile]

    enum CodingKeys: String, CodingKey {
        case source, groups
        case videoCount = "video_count"
        case sidecarCount = "sidecar_count"
        case totalBytes = "total_bytes"
        case unassignedSidecars = "unassigned_sidecars"
    }
}

struct ShootGroup: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: ProjectKind
    var files: [ScannedFile]
    let start: String
    let end: String

    var videos: [ScannedFile] { files.filter { $0.kind == "video" } }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}

struct ProjectRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var rootPath: String
    var sourcePath: String
    var kind: ProjectKind
    var createdAt: Date
    var indexedAssets: Int
    var visualSamples: Int
    var transcripts: Int?

    init(id: UUID = UUID(), name: String, rootPath: String, sourcePath: String, kind: ProjectKind, createdAt: Date = Date(), indexedAssets: Int = 0, visualSamples: Int = 0, transcripts: Int? = nil) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.sourcePath = sourcePath
        self.kind = kind
        self.createdAt = createdAt
        self.indexedAssets = indexedAssets
        self.visualSamples = visualSamples
        self.transcripts = transcripts
    }
}

struct MomentResult: Codable, Identifiable, Hashable {
    let assetID: String
    let sourcePath: String
    let query: String
    let score: Double
    let detectedStart: Double
    let detectedEnd: Double
    let handledStart: Double?
    let handledEnd: Double?
    let labels: [String]
    let transcript: String?

    var id: String { "\(assetID)-\(handledStart ?? detectedStart)-\(query)" }
    var fileName: String { URL(fileURLWithPath: sourcePath).lastPathComponent }

    enum CodingKeys: String, CodingKey {
        case query, score, labels, transcript
        case assetID = "asset_id"
        case sourcePath = "source_path"
        case detectedStart = "detected_start"
        case detectedEnd = "detected_end"
        case handledStart = "handled_start"
        case handledEnd = "handled_end"
    }
}

struct ProjectStatus: Codable {
    let projectRoot: String
    let exists: Bool
    let assets: Int
    let visualSamples: Int
    let transcripts: Int
    let indexPath: String

    enum CodingKeys: String, CodingKey {
        case exists, assets, transcripts
        case projectRoot = "project_root"
        case visualSamples = "visual_samples"
        case indexPath = "index_path"
    }
}

struct ResolveScaffoldResult: Codable {
    let project: String
    let projectRoot: String
    let source: String
    let sourceFiles: Int
    let imported: Int
    let snapshot: String
    let snapshotExported: Bool
    let timelineFPS: Double?
    let playbackFPS: Double?
    let frameRatesMatch: Bool

    enum CodingKeys: String, CodingKey {
        case project, source, imported, snapshot
        case projectRoot = "project_root"
        case sourceFiles = "source_files"
        case snapshotExported = "snapshot_exported"
        case timelineFPS = "timeline_fps"
        case playbackFPS = "playback_fps"
        case frameRatesMatch = "frame_rates_match"
    }
}

struct SelectsResult: Codable {
    let project: String
    let timeline: String
    let rangesRequested: Int
    let rangesAppended: Int
    let query: String
    let moments: Int
    let remainderTimeline: String?
    let remainderRangesRequested: Int?
    let remainderRangesAppended: Int?
    let coverageComplete: Bool?

    enum CodingKeys: String, CodingKey {
        case project, timeline, query, moments
        case rangesRequested = "ranges_requested"
        case rangesAppended = "ranges_appended"
        case remainderTimeline = "remainder_timeline"
        case remainderRangesRequested = "remainder_ranges_requested"
        case remainderRangesAppended = "remainder_ranges_appended"
        case coverageComplete = "coverage_complete"
    }
}

struct SmartSelectsCategoryResult: Codable, Hashable, Identifiable {
    let name: String
    let query: String
    let timeline: String?
    let moments: Int
    let rangesRequested: Int
    let rangesAppended: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, query, timeline, moments
        case rangesRequested = "ranges_requested"
        case rangesAppended = "ranges_appended"
    }
}

struct SmartSelectsResult: Codable {
    let project: String
    let profile: String
    let categories: [SmartSelectsCategoryResult]
    let categoryTimelinesCreated: Int
    let selectedRanges: Int
    let stringoutTimeline: String
    let stringoutRangesRequested: Int
    let stringoutRangesAppended: Int
    let remainderTimeline: String?
    let remainderRangesRequested: Int
    let remainderRangesAppended: Int
    let indexedAssets: Int
    let coverageComplete: Bool

    enum CodingKeys: String, CodingKey {
        case project, profile, categories
        case categoryTimelinesCreated = "category_timelines_created"
        case selectedRanges = "selected_ranges"
        case stringoutTimeline = "stringout_timeline"
        case stringoutRangesRequested = "stringout_ranges_requested"
        case stringoutRangesAppended = "stringout_ranges_appended"
        case remainderTimeline = "remainder_timeline"
        case remainderRangesRequested = "remainder_ranges_requested"
        case remainderRangesAppended = "remainder_ranges_appended"
        case indexedAssets = "indexed_assets"
        case coverageComplete = "coverage_complete"
    }
}

struct ActivityEntry: Identifiable, Hashable {
    let id = UUID()
    let date = Date()
    let message: String
    let isError: Bool
}

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatEvidence: Codable, Hashable, Identifiable {
    let sourcePath: String
    let start: Double
    let end: Double
    let score: Double
    let transcript: String?

    var id: String { "\(sourcePath)-\(start)-\(end)" }
    var fileName: String { URL(fileURLWithPath: sourcePath).lastPathComponent }
}

struct ChatMessage: Codable, Hashable, Identifiable {
    let id: UUID
    let projectID: UUID
    let role: ChatRole
    let text: String
    let evidence: [ChatEvidence]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        role: ChatRole,
        text: String,
        evidence: [ChatEvidence] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.role = role
        self.text = text
        self.evidence = evidence
        self.createdAt = createdAt
    }
}

enum ChatMemoryScope: String, Codable, CaseIterable, Identifiable {
    case global = "All projects"
    case project = "This project"

    var id: String { rawValue }
}

struct ChatMemoryItem: Codable, Hashable, Identifiable {
    let id: UUID
    let scope: ChatMemoryScope
    let projectID: UUID?
    let category: String
    let content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        scope: ChatMemoryScope,
        projectID: UUID?,
        category: String,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.projectID = scope == .project ? projectID : nil
        self.category = category
        self.content = content
        self.createdAt = createdAt
    }
}

struct ClaudeMemoryUpdate: Codable, Equatable {
    let scope: ChatMemoryScope
    let category: String
    let content: String
}

enum ClaudeAction: String, Codable {
    case answer
    case searchVisual = "search_visual"
    case searchTranscript = "search_transcript"
    case proposeSelects = "propose_selects"
    case proposeSmartSelects = "propose_smart_selects"
    case prepareResolve = "prepare_resolve"
}

struct ClaudeIntent: Codable, Equatable {
    let message: String
    let action: ClaudeAction
    let query: String?
    let timelineName: String?
    let searchMode: SearchMode?
    let profile: String?
    let memoryUpdates: [ClaudeMemoryUpdate]
    let preHandleSeconds: Double?
    let postHandleSeconds: Double?
    let minimumDurationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case message, action, query
        case timelineName = "timeline_name"
        case searchMode = "search_mode"
        case profile
        case memoryUpdates = "memory_updates"
        case preHandleSeconds = "pre_handle_seconds"
        case postHandleSeconds = "post_handle_seconds"
        case minimumDurationSeconds = "minimum_duration_seconds"
    }
}

enum PendingChatActionKind: String, Codable {
    case createSelects
    case createSmartSelects
    case prepareResolve
}

struct PendingChatAction: Identifiable, Hashable {
    let id = UUID()
    let projectID: UUID
    let kind: PendingChatActionKind
    let title: String
    let query: String?
    let timelineName: String?
    let searchMode: SearchMode?
    let profile: String?
    let rangeCount: Int
}

extension TimeInterval {
    var editorTimecode: String {
        let value = max(0, self)
        let hours = Int(value / 3600)
        let minutes = Int(value.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = value.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%02d:%05.2f", hours, minutes, seconds)
    }
}
