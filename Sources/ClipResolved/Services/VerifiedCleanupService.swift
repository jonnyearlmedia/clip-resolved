import Foundation
import OffloadCore
import OffloadEngine

struct VerifiedCleanupResult: Sendable {
    let filesDeleted: Int
    let bytesDeleted: Int64
}

struct CompletedIngestShoot: Codable, Identifiable, Sendable {
    var id = UUID()
    let shootName: String
    let projectName: String
    let projectRoot: String
    let mediaRoot: String
    let sourceLabel: String
    let filesVerified: Int
    let bytesVerified: Int64
    let addedToExistingProject: Bool
    let indexedAssets: Int
}

struct IngestCompletionSummary: Codable, Identifiable, Sendable {
    var id = UUID()
    let projectNames: [String]
    let filesVerified: Int
    let bytesVerified: Int64
    let cleanupPlans: [VerifiedCleanupPlan]
    let shoots: [CompletedIngestShoot]
    let shootsLeftOnSource: Int?
}

private struct CleanupFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Deletes only the exact source files recorded by a completed verified ingest.
/// Every destination is hash-checked again before the all-or-nothing wipe gate
/// is evaluated, and the upstream Wiper revalidates each source inode and hash
/// immediately before unlinking it.
actor VerifiedCleanupService {
    private struct PreparedPlan {
        let plan: VerifiedCleanupPlan
        let journal: Journal
        let verdict: WipeGate.Verdict
    }

    func cleanup(
        plans: [VerifiedCleanupPlan],
        currentSourceRoot: URL,
        currentVolumeUUID: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> VerifiedCleanupResult {
        guard !plans.isEmpty else {
            throw CleanupFailure(message: "There are no verified imported files to remove.")
        }

        let currentRoot = currentSourceRoot.standardizedFileURL.path
        var prepared: [PreparedPlan] = []
        let totalFiles = plans.reduce(0) { $0 + $1.session.files.count }
        var destinationsRechecked = 0

        // Preflight every selected shoot before deleting the first file. If one
        // destination or source no longer matches, the whole cleanup is blocked.
        for plan in plans {
            guard plan.sourceRoot == currentRoot else {
                throw CleanupFailure(message: "Cleanup is blocked because the selected source folder is not the source that was imported.")
            }
            guard plan.volumeUUID == currentVolumeUUID else {
                throw CleanupFailure(message: "Cleanup is blocked because this is not the same card or source used for the verified import.")
            }

            let projectPrefix = URL(fileURLWithPath: plan.projectRoot).standardizedFileURL.path + "/"
            for file in plan.session.files {
                progress("Rechecking destination file \(destinationsRechecked + 1) of \(totalFiles): \(file.fileName)")
                guard let expectedHash = file.sourceHashHex, !expectedHash.isEmpty else {
                    throw CleanupFailure(message: "Cleanup is blocked because \(file.fileName) has no verified source hash.")
                }
                guard let destinationPath = plan.destinationByFileID[file.id.uuidString] else {
                    throw CleanupFailure(message: "Cleanup is blocked because the verified destination for \(file.fileName) is missing from the manifest.")
                }
                let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
                guard destination.path.hasPrefix(projectPrefix) else {
                    throw CleanupFailure(message: "Cleanup is blocked because the destination for \(file.fileName) is outside its project.")
                }
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    throw CleanupFailure(message: "Cleanup is blocked because the copied file is missing: \(destination.lastPathComponent).")
                }
                let destinationHash = try await ChunkedIO.hashFile(destination, noCache: true)
                guard destinationHash == expectedHash else {
                    throw CleanupFailure(message: "Cleanup is blocked because the copied file no longer matches: \(destination.lastPathComponent).")
                }
                destinationsRechecked += 1
            }

            let sourceValues = try currentSourceRoot.resourceValues(forKeys: [.volumeIsReadOnlyKey])
            let journalRoot = URL(fileURLWithPath: plan.manifestRoot)
                .appendingPathComponent("cleanup-journal", isDirectory: true)
            let journal = Journal(
                directory: journalRoot,
                historyDir: URL(fileURLWithPath: plan.manifestRoot)
                    .appendingPathComponent("cleanup-history", isDirectory: true)
            )
            try await journal.begin(plan.session)
            try await journal.flushNow(plan.session.id)

            let verdict = WipeGate.evaluate(
                session: plan.session,
                policy: .afterNASVerify,
                cardMount: WipeGate.CardMountSnapshot(
                    volumeUUID: currentVolumeUUID,
                    rootPath: currentRoot,
                    isReadOnly: sourceValues.volumeIsReadOnly ?? false
                ),
                nasHealth: .healthy,
                statOf: WipeGate.liveStat,
                journalFlushed: true
            )
            guard verdict.allowed else {
                let reasons = verdict.blockers.map(\.description).joined(separator: "; ")
                throw CleanupFailure(message: "Cleanup is blocked: \(reasons)")
            }
            prepared.append(PreparedPlan(plan: plan, journal: journal, verdict: verdict))
        }

        var deleted = 0
        var bytes: Int64 = 0
        for item in prepared {
            let sizes = Dictionary(uniqueKeysWithValues: item.plan.session.files.map { ($0.id, $0.size) })
            let deletedBeforePlan = deleted
            let plannedDeletions = item.verdict.deletions
            let result = await Wiper.execute(
                deletions: plannedDeletions,
                journal: item.journal,
                sessionID: item.plan.session.id,
                fileIDs: Dictionary(uniqueKeysWithValues: item.verdict.deletions.map { ($0.fileID, $0) }),
                onProgress: { finished, _ in
                    let filename = URL(fileURLWithPath: plannedDeletions[finished - 1].absolutePath).lastPathComponent
                    progress("Removing imported source file \(deletedBeforePlan + finished) of \(totalFiles): \(filename)")
                }
            )
            if let stoppedEarly = result.stoppedEarly {
                throw CleanupFailure(message: stoppedEarly)
            }
            Wiper.pruneEmptyDirectories(deletions: item.verdict.deletions, cardRoot: currentRoot)
            deleted += result.filesDeleted
            bytes += item.verdict.deletions.prefix(result.filesDeleted).reduce(0) {
                $0 + (sizes[$1.fileID] ?? 0)
            }
            await item.journal.setWipeReport(
                WipeReport(ran: true, filesDeleted: result.filesDeleted, finishedAt: Date()),
                in: item.plan.session.id
            )
            await item.journal.setSessionState(.done, in: item.plan.session.id)
            await item.journal.setEnded(in: item.plan.session.id)
            try await item.journal.flushNow(item.plan.session.id)
            try await item.journal.complete(item.plan.session.id)

            let receipt: [String: Any] = [
                "schema": 1,
                "cleanup_plan": item.plan.id.uuidString,
                "source_root": currentRoot,
                "files_deleted": result.filesDeleted,
                "completed_at": ISO8601DateFormatter().string(from: Date()),
            ]
            let receiptData = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try receiptData.write(
                to: URL(fileURLWithPath: item.plan.manifestRoot)
                    .appendingPathComponent("cleanup-complete-\(item.plan.id.uuidString).json"),
                options: .atomic
            )
        }

        return VerifiedCleanupResult(filesDeleted: deleted, bytesDeleted: bytes)
    }
}
