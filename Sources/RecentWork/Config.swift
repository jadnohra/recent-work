import Foundation

public struct Config: Sendable {
    public let watch: [String]
    public let retention: Retention
    public let outputDir: String
    public let debounceSeconds: Double

    public struct Retention: Sendable {
        public let maxFiles: Int
        public let maxAgeHours: Int
    }

    public init() {
        self.watch = Self.allCandidateWatchDirsExpanded()
        self.retention = Retention(maxFiles: 100, maxAgeHours: 48)
        self.outputDir = "~/RecentWork"
        self.debounceSeconds = 2.0
    }

    /// All candidate watch directories — always included so future
    /// directories are picked up on daemon restart.
    public static let candidateWatchDirs: [String] = [
        "~/Documents",
        "~/Desktop",
        "~/Downloads",
        "~/Projects",
        "~/Developer",
        "~/repos",
        "~/Code",
        "~/src",
    ]

    /// Returns absolute paths for all candidates
    public static func allCandidateWatchDirsExpanded() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return candidateWatchDirs.map { $0.replacingOccurrences(of: "~", with: home) }
    }

    /// Returns (path, exists) pairs for display
    public static func detectWatchDirs() -> [(path: String, exists: Bool)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        return candidateWatchDirs.map { tildePath in
            let abs = tildePath.replacingOccurrences(of: "~", with: home)
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: abs, isDirectory: &isDir) && isDir.boolValue
            return (path: abs, exists: exists)
        }
    }

    /// Resolved output directory URL
    public var outputURL: URL {
        URL(fileURLWithPath: (outputDir as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Resolved watch directory URLs
    public var watchURLs: [URL] {
        watch.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }
}
