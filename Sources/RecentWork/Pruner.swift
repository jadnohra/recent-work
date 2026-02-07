import Foundation
import os

public final class Pruner: @unchecked Sendable {
    private let outputDir: URL
    private let stateStore: StateStore
    private let maxFiles: Int
    private let maxAgeHours: Int
    private let logger = Logger(subsystem: "com.recentwork", category: "Pruner")
    private let fm = FileManager.default
    private var timer: Timer?

    public init(
        outputDir: URL,
        stateStore: StateStore,
        maxFiles: Int,
        maxAgeHours: Int
    ) {
        self.outputDir = outputDir
        self.stateStore = stateStore
        self.maxFiles = maxFiles
        self.maxAgeHours = maxAgeHours
    }

    /// Run a full prune cycle
    public func prune() {
        removeBrokenSymlinks()
        pruneByAge()
        pruneByCount()
    }

    /// Start a periodic timer that prunes every `interval` seconds
    public func startPeriodicPruning(interval: TimeInterval = 60) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.prune()
        }
    }

    public func stopPeriodicPruning() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Broken symlinks

    private func removeBrokenSymlinks() {
        let entries = stateStore.allEntries()
        for (name, entry) in entries {
            let symlinkPath = outputDir.appendingPathComponent(name).path

            // Check if the symlink itself exists
            var isDir: ObjCBool = false
            let symlinkExists = fm.fileExists(atPath: symlinkPath, isDirectory: &isDir)

            if !symlinkExists {
                // Symlink file was deleted externally
                stateStore.remove(name)
                logger.debug("Cleaned orphaned state entry: \(name)")
                continue
            }

            // Check if the target exists
            let targetExists = fm.fileExists(atPath: entry.originalPath)
            if !targetExists {
                try? fm.removeItem(atPath: symlinkPath)
                stateStore.remove(name)
                logger.info("Removed broken symlink: \(name)")
            }
        }
    }

    // MARK: - Age-based pruning

    private func pruneByAge() {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeHours) * 3600)
        let entries = stateStore.allEntries()

        for (name, entry) in entries where entry.timestamp < cutoff {
            let symlinkPath = outputDir.appendingPathComponent(name).path
            try? fm.removeItem(atPath: symlinkPath)
            stateStore.remove(name)
            logger.info("Pruned expired symlink: \(name)")
        }
    }

    // MARK: - Count-based pruning

    private func pruneByCount() {
        let sorted = stateStore.sortedByAge()  // oldest first
        let excess = sorted.count - maxFiles
        guard excess > 0 else { return }

        for (name, _) in sorted.prefix(excess) {
            let symlinkPath = outputDir.appendingPathComponent(name).path
            try? fm.removeItem(atPath: symlinkPath)
            stateStore.remove(name)
            logger.info("Pruned over-limit symlink: \(name)")
        }
    }
}
