import Foundation

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case project = "Project"
    case search = "Footage Search"
    case chat = "Project Chat"
    case ingest = "Import Media"
    case activity = "Activity"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .project: "square.stack.3d.up"
        case .search: "sparkle.magnifyingglass"
        case .chat: "bubble.left.and.bubble.right"
        case .ingest: "externaldrive.badge.plus"
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

enum ShootProfile: String, Codable, CaseIterable, Identifiable {
    case restaurant = "Restaurant / Hospitality"
    case communityStory = "Interview / Community Story"
    case event = "Event / Family"

    var id: String { rawValue }

    var backendName: String {
        switch self {
        case .restaurant: "restaurant"
        case .communityStory: "community-story"
        case .event: "event"
        }
    }

    var packageTitle: String {
        switch self {
        case .restaurant: "Restaurant SELECTS Package"
        case .communityStory: "Community Story SELECTS Package"
        case .event: "Chronological Event Package"
        }
    }

    var summary: String {
        switch self {
        case .restaurant:
            "Food, interiors, storefront, drinks, signage, and detail-driven b-roll."
        case .communityStory:
            "Interview setups, people, process, products, locations, and cutaways."
        case .event:
            "Chronology first, then ceremony, speeches, reactions, groups, details, food, and venue."
        }
    }
}

enum ProjectSourceKind: String, Codable, CaseIterable, Identifiable {
    case camera = "Camera"
    case audio = "Audio"
    var id: String { rawValue }
    var backendName: String { rawValue.lowercased() }
}

struct ProjectSourceRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var label: String
    var path: String
    var kind: ProjectSourceKind
    var addedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        path: String,
        kind: ProjectSourceKind = .camera,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.path = path
        self.kind = kind
        self.addedAt = addedAt
    }
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
    let sourceKind: ProjectSourceKind
    let start: String
    let end: String
    let videoCount: Int
    let audioCount: Int
    let fileCount: Int
    let totalBytes: Int64
    let files: [ScannedFile]

    enum CodingKeys: String, CodingKey {
        case id, start, end, files
        case suggestedName = "suggested_name"
        case sourceKind = "source_kind"
        case videoCount = "video_count"
        case audioCount = "audio_count"
        case fileCount = "file_count"
        case totalBytes = "total_bytes"
    }
}

struct ScanPayload: Codable {
    let source: String
    let videoCount: Int
    let audioCount: Int
    let sidecarCount: Int
    let totalBytes: Int64
    let groups: [ScannedGroupPayload]
    let unassignedSidecars: [ScannedFile]

    enum CodingKeys: String, CodingKey {
        case source, groups
        case videoCount = "video_count"
        case audioCount = "audio_count"
        case sidecarCount = "sidecar_count"
        case totalBytes = "total_bytes"
        case unassignedSidecars = "unassigned_sidecars"
    }
}

struct ShootGroup: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: ProjectKind
    var sourceLabel: String
    var sourceKind: ProjectSourceKind
    var files: [ScannedFile]
    let start: String
    let end: String

    var videos: [ScannedFile] { files.filter { $0.kind == "video" } }
    var audioFiles: [ScannedFile] { files.filter { $0.kind == "audio" } }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}

struct ProjectRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var rootPath: String
    var sourcePath: String
    var kind: ProjectKind
    var profile: ShootProfile
    var sources: [ProjectSourceRecord]
    var createdAt: Date
    var indexedAssets: Int
    var visualSamples: Int
    var transcripts: Int?

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        sourcePath: String,
        kind: ProjectKind,
        profile: ShootProfile? = nil,
        sources: [ProjectSourceRecord]? = nil,
        createdAt: Date = Date(),
        indexedAssets: Int = 0,
        visualSamples: Int = 0,
        transcripts: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.sourcePath = sourcePath
        self.kind = kind
        self.profile = profile ?? (kind == .personal ? .event : .communityStory)
        self.sources = sources ?? [
            ProjectSourceRecord(
                label: Self.inferSourceLabel(sourcePath),
                path: sourcePath,
                kind: .camera,
                addedAt: createdAt
            )
        ]
        self.createdAt = createdAt
        self.indexedAssets = indexedAssets
        self.visualSamples = visualSamples
        self.transcripts = transcripts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rootPath, sourcePath, kind, profile, sources, createdAt
        case indexedAssets, visualSamples, transcripts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        rootPath = try values.decode(String.self, forKey: .rootPath)
        sourcePath = try values.decode(String.self, forKey: .sourcePath)
        kind = try values.decode(ProjectKind.self, forKey: .kind)
        profile = try values.decodeIfPresent(ShootProfile.self, forKey: .profile)
            ?? (kind == .personal ? .event : .communityStory)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        sources = try values.decodeIfPresent([ProjectSourceRecord].self, forKey: .sources)
            ?? [ProjectSourceRecord(
                label: Self.inferSourceLabel(sourcePath),
                path: sourcePath,
                kind: .camera,
                addedAt: createdAt
            )]
        indexedAssets = try values.decodeIfPresent(Int.self, forKey: .indexedAssets) ?? 0
        visualSamples = try values.decodeIfPresent(Int.self, forKey: .visualSamples) ?? 0
        transcripts = try values.decodeIfPresent(Int.self, forKey: .transcripts)
    }

    static func inferSourceLabel(_ path: String, kind: ProjectSourceKind = .camera) -> String {
        let lower = path.lowercased()
        if kind == .audio {
            if lower.contains("mic 2") || lower.contains("mic_2") || lower.contains("mic2") { return "DJI MIC 2" }
            if lower.contains("mic mini") || lower.contains("mic_mini") { return "DJI MIC MINI" }
            if lower.contains("zoom") { return "ZOOM RECORDER" }
            let name = URL(fileURLWithPath: path).lastPathComponent
            return name.isEmpty ? "EXTERNAL AUDIO" : name.uppercased()
        }
        if lower.contains("insta360") || lower.contains("go ultra") { return "INSTA360 GO ULTRA" }
        if lower.contains("iphone") || lower.contains("apple") { return "IPHONE" }
        if lower.contains("osmo") || lower.contains("dji") || lower.contains("raw footage") { return "OSMO" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "CAMERA" : name.uppercased()
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
    let audioFiles: Int?

    enum CodingKeys: String, CodingKey {
        case project, source, imported, snapshot
        case projectRoot = "project_root"
        case sourceFiles = "source_files"
        case snapshotExported = "snapshot_exported"
        case timelineFPS = "timeline_fps"
        case playbackFPS = "playback_fps"
        case frameRatesMatch = "frame_rates_match"
        case audioFiles = "audio_files"
    }
}

struct AudioSyncResult: Codable {
    let project: String
    let syncMode: String
    let videos: Int
    let audioFiles: Int
    let retainEmbeddedAudio: Bool
    let synced: Bool

    enum CodingKeys: String, CodingKey {
        case project, videos, synced
        case syncMode = "sync_mode"
        case audioFiles = "audio_files"
        case retainEmbeddedAudio = "retain_embedded_audio"
    }
}

struct MulticamResult: Codable {
    let project: String
    let name: String
    let syncMode: String
    let cameraSources: [String]
    let sourceClips: Int
    let multicamClipsCreated: Int
    let created: Bool

    enum CodingKeys: String, CodingKey {
        case project, name, created
        case syncMode = "sync_mode"
        case cameraSources = "camera_sources"
        case sourceClips = "source_clips"
        case multicamClipsCreated = "multicam_clips_created"
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

struct ResolveTimelineState: Codable {
    let project: String
    let timelines: [String]
    let currentTimeline: String?

    enum CodingKeys: String, CodingKey {
        case project, timelines
        case currentTimeline = "current_timeline"
    }
}

struct OpenTimelineResult: Codable {
    let project: String
    let timeline: String
    let opened: Bool
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

struct ChatSuggestedAction: Codable, Hashable {
    let query: String
    let timelineName: String
    let searchMode: SearchMode
    let rangeCount: Int
}

struct ChatMessage: Codable, Hashable, Identifiable {
    let id: UUID
    let projectID: UUID
    let role: ChatRole
    let text: String
    let evidence: [ChatEvidence]
    let suggestedAction: ChatSuggestedAction?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        role: ChatRole,
        text: String,
        evidence: [ChatEvidence] = [],
        suggestedAction: ChatSuggestedAction? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.role = role
        self.text = text
        self.evidence = evidence
        self.suggestedAction = suggestedAction
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
    case openTimeline
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
