import AppKit
import Foundation

enum ResolveApplicationError: LocalizedError {
    case notInstalled
    case launchFailed(String)
    case startupTimedOut
    case frameRateMismatch(Double)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "DaVinci Resolve is not installed in Applications. Install or move it there, then try again."
        case .launchFailed(let message):
            "DaVinci Resolve could not be opened: \(message)"
        case .startupTimedOut:
            "DaVinci Resolve opened but did not become ready. Finish any startup dialog in Resolve, then try again."
        case .frameRateMismatch(let fps):
            "Resolve opened the project, but its playback frame rate must be set to \(fps) before Clip Resolved can create SELECTS."
        }
    }
}

@MainActor
struct ResolveApplicationService {
    static let bundleIdentifier = "com.blackmagic-design.DaVinciResolve"
    static let applicationURL = URL(fileURLWithPath: "/Applications/DaVinci Resolve/DaVinci Resolve.app")

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    /// Opens the already-installed editor. The calling workflow still verifies
    /// scripting readiness before it performs any confirmed Resolve mutation.
    func openIfNeeded() async throws -> Bool {
        guard !isRunning else { return false }
        guard FileManager.default.fileExists(atPath: Self.applicationURL.path) else {
            throw ResolveApplicationError.notInstalled
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: Self.applicationURL, configuration: configuration) { application, error in
                if let error {
                    continuation.resume(throwing: ResolveApplicationError.launchFailed(error.localizedDescription))
                } else if application == nil {
                    continuation.resume(throwing: ResolveApplicationError.launchFailed("macOS did not return an application process."))
                } else {
                    continuation.resume()
                }
            }
        }
        return true
    }
}

extension BackendError {
    var isResolveConnectionUnavailable: Bool {
        guard case .commandFailed(_, let output) = self else { return false }
        let lowered = output.lowercased()
        return lowered.contains("could not connect to davinci resolve")
            || lowered.contains("failed to get resolve object")
    }
}
