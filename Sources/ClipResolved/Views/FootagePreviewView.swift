import AVFoundation
import AVKit
import AppKit
import SwiftUI

/// A large playback surface for judging footage. Only the native player controller crosses
/// the AppKit boundary, avoiding AVKit's crashing SwiftUI `VideoPlayer` while preserving normal
/// mouse and responder routing for every control.
struct FootagePreviewPresentation: View {
    let evidence: ChatEvidence
    let onClose: () -> Void

    var body: some View {
        FootagePreviewSidebarView(evidence: evidence, onClose: onClose)
            .frame(minWidth: 960, idealWidth: 1_120, minHeight: 700, idealHeight: 780)
    }
}

struct FootagePreviewSidebarView: NSViewControllerRepresentable {
    @Environment(\.cr) private var cr
    let evidence: ChatEvidence
    let onClose: () -> Void

    func makeNSViewController(context: Context) -> FootagePreviewSidebarController {
        let controller = FootagePreviewSidebarController(evidence: evidence, palette: cr, onClose: onClose)
        controller.prepareAndPlay()
        return controller
    }

    func updateNSViewController(_ controller: FootagePreviewSidebarController, context: Context) { }

    static func dismantleNSViewController(_ controller: FootagePreviewSidebarController, coordinator: ()) {
        controller.stop()
    }
}

@MainActor
final class FootagePreviewSidebarController: NSViewController {
    let evidence: ChatEvidence
    let palette: CRPalette
    let player: AVPlayer
    let playerView = AVPlayerView(frame: .zero)
    let selectedDuration: Double

    private let onClose: () -> Void
    private var loadingTask: Task<Void, Never>?
    private weak var modeLabel: NSTextField?
    private weak var replayButton: NSButton?
    private weak var sourceToggleButton: NSButton?
    private var showingFullSource = false

    init(evidence: ChatEvidence, palette: CRPalette = .dark, onClose: @escaping () -> Void = {}) {
        self.evidence = evidence
        self.palette = palette
        self.onClose = onClose

        let start = max(0, evidence.start)
        let end = max(start + 0.1, evidence.end)
        selectedDuration = end - start
        player = AVPlayer()

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = makeContentView()
    }

    func prepareAndPlay() {
        showingFullSource = false
        updateModeControls()
        loadingTask?.cancel()
        let sourceURL = URL(fileURLWithPath: evidence.sourcePath)
        let start = max(0, evidence.start)
        let end = max(start + 0.1, evidence.end)
        loadingTask = Task { [weak self] in
            guard let item = await Self.makeTrimmedPlayerItem(sourceURL: sourceURL, start: start, end: end),
                  !withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }),
                  let self else { return }
            player.replaceCurrentItem(with: item)
            replayMatch()
        }
    }

    func replayMatch() {
        let destination = showingFullSource ? evidence.start : 0
        let time = CMTime(seconds: max(0, destination), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] finished in
            if finished { player?.play() }
        }
    }

    func stop() {
        loadingTask?.cancel()
        loadingTask = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func makeContentView() -> NSView {
        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(palette.card).cgColor

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close preview")!, target: self, action: #selector(closePressed))
        close.bezelStyle = .circular
        close.isBordered = false
        close.contentTintColor = NSColor(palette.textSecondary)

        let title = NSTextField(labelWithString: evidence.fileName)
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = NSColor(palette.text)
        title.lineBreakMode = .byTruncatingMiddle

        let range = NSTextField(
            labelWithString: "SELECTED MOMENT  •  \(selectedDuration.formatted(.number.precision(.fractionLength(1)))) SEC"
        )
        range.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        range.textColor = NSColor(palette.accent)
        modeLabel = range

        let sourceRange = NSTextField(
            labelWithString: "Source \(evidence.start.editorTimecode) – \(evidence.end.editorTimecode)"
        )
        sourceRange.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sourceRange.textColor = NSColor(palette.textSecondary)

        let headerText = NSStackView(views: [title, range, sourceRange])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 4

        let headerSpacer = NSView(frame: .zero)
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let heading = NSStackView(views: [headerText, headerSpacer, close])
        heading.orientation = .horizontal
        heading.alignment = .top
        heading.spacing = 10

        let divider = NSBox(frame: .zero)
        divider.boxType = .separator

        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.translatesAutoresizingMaskIntoConstraints = false

        let replay = NSButton(title: "Replay Range", target: self, action: #selector(replayPressed))
        replay.bezelStyle = .rounded
        replayButton = replay

        let toggleSource = NSButton(title: "View Full Source", target: self, action: #selector(toggleSourcePressed))
        toggleSource.bezelStyle = .rounded
        sourceToggleButton = toggleSource

        let reveal = NSButton(title: "Reveal in Finder", target: self, action: #selector(revealPressed))
        reveal.bezelStyle = .rounded

        let controls = NSStackView(views: [replay, toggleSource, reveal])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8

        let mediaKind = URL(fileURLWithPath: evidence.sourcePath).pathExtension.lowercased() == "wav" ? "WAV" : "video"
        let note = NSTextField(
            wrappingLabelWithString: "This player contains only this selected range. It references the original \(mediaKind) on the source device; no duplicate preview file was rendered."
        )
        note.font = .systemFont(ofSize: 11)
        note.textColor = NSColor(palette.textTertiary)

        let content = NSStackView(views: [heading, divider, playerView, controls, note])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            heading.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            playerView.heightAnchor.constraint(equalTo: playerView.widthAnchor, multiplier: 9.0 / 16.0),
            controls.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            note.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        return root
    }

    private static func makeTrimmedPlayerItem(sourceURL: URL, start: Double, end: Double) async -> AVPlayerItem? {
        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        let sourceRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )

        for mediaType in [AVMediaType.video, AVMediaType.audio] {
            guard let sourceTrack = try? await asset.loadTracks(withMediaType: mediaType).first,
                  let destinationTrack = composition.addMutableTrack(
                    withMediaType: mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { continue }
            try? destinationTrack.insertTimeRange(sourceRange, of: sourceTrack, at: .zero)
            if mediaType == .video,
               let transform = try? await sourceTrack.load(.preferredTransform) {
                destinationTrack.preferredTransform = transform
            }
        }

        guard !composition.tracks.isEmpty else { return nil }
        return AVPlayerItem(asset: composition)
    }

    @objc private func replayPressed() {
        replayMatch()
    }

    @objc private func toggleSourcePressed() {
        loadingTask?.cancel()
        let sourceURL = URL(fileURLWithPath: evidence.sourcePath)
        if showingFullSource {
            prepareAndPlay()
            return
        }
        showingFullSource = true
        updateModeControls()
        player.replaceCurrentItem(with: AVPlayerItem(url: sourceURL))
        replayMatch()
    }

    @objc private func revealPressed() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: evidence.sourcePath)])
    }

    @objc private func closePressed() {
        onClose()
    }

    private func updateModeControls() {
        modeLabel?.stringValue = showingFullSource
            ? "FULL SOURCE  •  STARTED AT SELECTED MOMENT"
            : "SELECTED MOMENT  •  \(selectedDuration.formatted(.number.precision(.fractionLength(1)))) SEC"
        sourceToggleButton?.title = showingFullSource ? "View Selected Range" : "View Full Source"
        replayButton?.title = showingFullSource ? "Replay from Selection" : "Replay Range"
    }
}

struct EvidenceThumbnailView: View {
    @Environment(\.cr) private var cr
    let evidence: ChatEvidence
    var width: CGFloat = 144
    var height: CGFloat = 81
    @StateObject private var loader = FootageThumbnailLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CRStripe(cornerRadius: 0)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(cr.border))
        .task(id: evidence.id) {
            loader.load(path: evidence.sourcePath, seconds: evidence.start)
        }
    }
}

/// A real frame from source media for pre-ingest shoot identification.
/// This reads the mounted original in place and never creates proxy media.
struct FootageFrameThumbnailView: View {
    @Environment(\.cr) private var cr
    let path: String
    let seconds: Double
    var cornerRadius: CGFloat = 5
    @StateObject private var loader = FootageThumbnailLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CRStripe(cornerRadius: 0)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(cr.border))
        .task(id: "\(path)#\(seconds)") {
            loader.load(path: path, seconds: seconds)
        }
        .accessibilityLabel("Frame from \(URL(fileURLWithPath: path).lastPathComponent)")
    }
}

final class FootageThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private var requestID = UUID()

    func load(path: String, seconds: Double) {
        let currentRequest = UUID()
        requestID = currentRequest
        image = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 448, height: 252)
            let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            let cgImage = try? generator.copyCGImage(at: time, actualTime: nil)
            let image = cgImage.map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async {
                guard self?.requestID == currentRequest else { return }
                self?.image = image
            }
        }
    }
}
