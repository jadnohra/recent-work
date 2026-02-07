import Foundation

public enum Paths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// `~/RecentWork/`
    public static var defaultOutputDir: URL {
        home.appendingPathComponent("RecentWork", isDirectory: true)
    }

    /// `~/RecentWork/.recent-work/`
    public static func stateDir(outputDir: URL) -> URL {
        outputDir.appendingPathComponent(".recent-work", isDirectory: true)
    }

    /// `~/RecentWork/.recent-work/state.json`
    public static func stateFile(outputDir: URL) -> URL {
        stateDir(outputDir: outputDir).appendingPathComponent("state.json")
    }

    /// `~/Library/LaunchAgents/com.recentwork.daemon.plist`
    public static var launchdPlist: URL {
        home.appendingPathComponent("Library/LaunchAgents/com.recentwork.daemon.plist")
    }

    /// `~/Library/Logs/recent-work/`
    public static var logDir: URL {
        home.appendingPathComponent("Library/Logs/recent-work", isDirectory: true)
    }

    /// Label used in the launchd plist
    public static let launchdLabel = "com.recentwork.daemon"
}
