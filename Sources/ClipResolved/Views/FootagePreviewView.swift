import AVFoundation
import AVKit
import AppKit
import SwiftUI

struct FootagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let evidence: ChatEvidence
    @StateObject private var controller: FootagePreviewController

    init(evidence: ChatEvidence) {
        self.evidence = evidence
        _controller = StateObject(wrappedValue: FootagePreviewController(evidence: evidence))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(evidence.fileName).font(.title2.bold())
                    Text("Matched range \(evidence.start.editorTimecode) – \(evidence.end.editorTimecode)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VideoPlayer(player: controller.player)
                .frame(minWidth: 780, minHeight: 438)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Button {
                    controller.replayMatch()
                } label: {
                    Label("Replay Match", systemImage: "backward.end.fill")
                }
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: evidence.sourcePath)])
                } label: {
                    Label("Reveal Original", systemImage: "folder")
                }

                Spacer()
                Text("Playback starts at the handled in point and pauses at the out point. Scrub freely to inspect context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 840, minHeight: 560)
        .onAppear { controller.replayMatch() }
        .onDisappear { controller.stop() }
    }
}

struct EvidenceThumbnailView: View {
    let evidence: ChatEvidence
    @StateObject private var loader = FootageThumbnailLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(width: 112, height: 63)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.5)))
        .task(id: evidence.id) {
            loader.load(path: evidence.sourcePath, seconds: evidence.start)
        }
    }
}

final class FootagePreviewController: ObservableObject {
    let player: AVPlayer
    private let start: Double
    private let end: Double
    private var timeObserver: Any?

    init(evidence: ChatEvidence) {
        start = evidence.start
        end = evidence.end
        player = AVPlayer(url: URL(fileURLWithPath: evidence.sourcePath))
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, time.seconds.isFinite, time.seconds >= self.end else { return }
            self.player.pause()
        }
    }

    func replayMatch() {
        let target = CMTime(seconds: start, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished { self?.player.play() }
        }
    }

    func stop() {
        player.pause()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
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
