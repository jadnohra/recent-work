import CryptoKit
import Foundation
import os

public final class SymlinkManager: @unchecked Sendable {
    private let outputDir: URL
    private let stateStore: StateStore
    private let logger = Logger(subsystem: "com.recentwork", category: "SymlinkManager")
    private let fm = FileManager.default

    public init(
        outputDir: URL,
        stateStore: StateStore
    ) {
        self.outputDir = outputDir
        self.stateStore = stateStore
    }

    /// Creates a symlink for the given file URL. Returns the symlink name if created.
    @discardableResult
    public func createSymlink(for fileURL: URL) -> String? {
        // Verify source exists
        guard fm.fileExists(atPath: fileURL.path) else {
            logger.debug("Source file no longer exists: \(fileURL.path)")
            return nil
        }

        let filename = fileURL.lastPathComponent

        // Skip hidden files and junk
        guard !shouldSkip(filename: filename) else {
            return nil
        }

        // Check if we already have a symlink pointing to this file
        if let existing = findExistingSymlink(for: fileURL) {
            let entry = LinkEntry(
                originalPath: fileURL.path,
                timestamp: Date(),
                symlinkName: existing
            )
            stateStore.set(entry)
            logger.debug("Updated timestamp for existing symlink: \(existing)")
            return existing
        }

        // Determine symlink name using collision strategy
        let symlinkName = resolveSymlinkName(for: fileURL)
        let symlinkURL = outputDir.appendingPathComponent(symlinkName)

        // Remove existing symlink at this location if any
        if fm.fileExists(atPath: symlinkURL.path) || (try? fm.attributesOfItem(atPath: symlinkURL.path)) != nil {
            try? fm.removeItem(at: symlinkURL)
            stateStore.remove(symlinkName)
        }

        do {
            try fm.createSymbolicLink(at: symlinkURL, withDestinationURL: fileURL)
            let entry = LinkEntry(
                originalPath: fileURL.path,
                timestamp: Date(),
                symlinkName: symlinkName
            )
            stateStore.set(entry)
            logger.info("Created symlink: \(symlinkName) → \(fileURL.path)")
            return symlinkName
        } catch {
            logger.error("Failed to create symlink: \(error.localizedDescription)")
            return nil
        }
    }

    /// Remove a specific symlink by name
    public func removeSymlink(named name: String) {
        let url = outputDir.appendingPathComponent(name)
        try? fm.removeItem(at: url)
        stateStore.remove(name)
    }

    /// Remove all symlinks in the output directory
    public func removeAll() {
        let entries = stateStore.allEntries()
        for (name, _) in entries {
            let url = outputDir.appendingPathComponent(name)
            try? fm.removeItem(at: url)
        }
        stateStore.clear()
        logger.info("Cleared all symlinks")
    }

    // MARK: - Filtering

    private static let skippedExtensions: Set<String> = [
        "o", "a", "dylib", "so", "class", "pyc", "pyo",
        "swiftdeps", "hmap", "modulemap", "wasm",
        "exe", "dll", "bin",
        "zip", "tar", "gz", "tgz", "rar", "7z", "dmg", "iso", "pkg",
        "tmp", "swp", "swo", "bak", "orig",
        "pbxproj", "xcscheme", "plist",
        "log", "pid", "cache", "map",
        "sqlite", "sqlite-wal", "sqlite-shm", "db",
    ]

    private static let skippedFilenames: Set<String> = [
        ".DS_Store",
        "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
        "Podfile.lock", "Package.resolved", "Cargo.lock",
        "composer.lock", "Gemfile.lock", "poetry.lock", "flake.lock",
        "output-file-map.json",
    ]

    private func shouldSkip(filename: String) -> Bool {
        // Hidden files
        if filename.hasPrefix(".") { return true }

        // Known junk filenames
        if Self.skippedFilenames.contains(filename) { return true }

        // Known junk extensions
        let ext = (filename as NSString).pathExtension.lowercased()
        if Self.skippedExtensions.contains(ext) { return true }

        return false
    }

    // MARK: - Naming

    private func resolveSymlinkName(for fileURL: URL) -> String {
        let filename = fileURL.lastPathComponent
        let symlinkURL = outputDir.appendingPathComponent(filename)

        // Strategy 1: Original filename
        if !fm.fileExists(atPath: symlinkURL.path) && stateStore.get(filename) == nil {
            return filename
        }

        // Strategy 2: ParentDir-filename
        let parentName = fileURL.deletingLastPathComponent().lastPathComponent
        let prefixedName = "\(parentName)-\(filename)"
        let prefixedURL = outputDir.appendingPathComponent(prefixedName)
        if !fm.fileExists(atPath: prefixedURL.path) && stateStore.get(prefixedName) == nil {
            return prefixedName
        }

        // Strategy 3: filename_XXXX (4-char hash)
        let hash = shortHash(fileURL.path)
        let ext = fileURL.pathExtension
        let stem = (filename as NSString).deletingPathExtension
        let hashedName = ext.isEmpty ? "\(stem)_\(hash)" : "\(stem)_\(hash).\(ext)"
        return hashedName
    }

    private func shortHash(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.prefix(2).map { String(format: "%02x", $0) }.joined()
    }

    private func findExistingSymlink(for fileURL: URL) -> String? {
        let entries = stateStore.allEntries()
        for (name, entry) in entries {
            if entry.originalPath == fileURL.path {
                return name
            }
        }
        return nil
    }
}
