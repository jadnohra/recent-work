import Foundation
import os

public struct LinkEntry: Codable, Sendable {
    public var originalPath: String
    public var timestamp: Date
    public var symlinkName: String

    public init(originalPath: String, timestamp: Date, symlinkName: String) {
        self.originalPath = originalPath
        self.timestamp = timestamp
        self.symlinkName = symlinkName
    }
}

public final class StateStore: @unchecked Sendable {
    private let fileURL: URL
    private var entries: [String: LinkEntry] = [:]
    private let logger = Logger(subsystem: "com.recentwork", category: "StateStore")
    private let lock = NSLock()

    public init(outputDir: URL) {
        self.fileURL = Paths.stateFile(outputDir: outputDir)
    }

    // MARK: - Persistence

    public func load() {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = [:]
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([String: LinkEntry].self, from: data)
        } catch {
            logger.warning("Failed to load state: \(error.localizedDescription)")
            entries = [:]
        }
    }

    public func save() {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)

            // Atomic write: write to temp, then rename
            let tmpURL = fileURL.appendingPathExtension("tmp")
            try data.write(to: tmpURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
        } catch {
            logger.error("Failed to save state: \(error.localizedDescription)")
        }
    }

    // MARK: - Access

    public func get(_ symlinkName: String) -> LinkEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[symlinkName]
    }

    public func set(_ entry: LinkEntry) {
        lock.lock()
        entries[entry.symlinkName] = entry
        lock.unlock()
        save()
    }

    public func remove(_ symlinkName: String) {
        lock.lock()
        entries.removeValue(forKey: symlinkName)
        lock.unlock()
        save()
    }

    public func allEntries() -> [String: LinkEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        save()
    }

    /// Returns entries sorted by timestamp, oldest first
    public func sortedByAge() -> [(String, LinkEntry)] {
        let snapshot = allEntries()
        return snapshot.sorted { $0.value.timestamp < $1.value.timestamp }
    }
}
