import ArgumentParser
import Foundation
import RecentWork

@main
struct RecentWorkCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recent-work",
        abstract: "Monitors file writes and maintains a Finder-friendly folder of symlinks to recent files.",
        subcommands: [
            Init.self,
            Start.self,
            Stop.self,
            Status.self,
            List.self,
            Clear.self,
            Uninstall.self,
        ]
    )
}

// MARK: - Init

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "First-time setup: create output dir and install launchd plist."
    )

    @Flag(name: .long, help: "Skip adding to Finder sidebar")
    var noSidebar = false

    func run() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let config = Config()

        print("recent-work setup\n")

        let detected = Config.detectWatchDirs().filter(\.exists)
        let dirs = detected.map { $0.path.replacingOccurrences(of: home, with: "~") }
        print("Watching: \(dirs.joined(separator: ", "))")
        print("Tracking: all files")
        print("Max files: \(config.retention.maxFiles), max age: \(config.retention.maxAgeHours)h")

        try fm.createDirectory(at: config.outputURL, withIntermediateDirectories: true)
        print("Output: \(config.outputURL.path)")

        try fm.createDirectory(
            at: Paths.stateDir(outputDir: config.outputURL),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(at: Paths.logDir, withIntermediateDirectories: true)

        let plist = generateLaunchdPlist()
        try fm.createDirectory(
            at: Paths.launchdPlist.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try plist.write(to: Paths.launchdPlist, atomically: true, encoding: .utf8)

        if !noSidebar {
            pinToFinderSidebar(url: config.outputURL)
        }

        print("\nDone! Run 'recent-work start' to begin watching.")
    }
}

// MARK: - Start

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the file watcher daemon."
    )

    @Flag(name: .long, help: "Run in foreground instead of as a launchd service")
    var foreground = false

    func run() throws {
        if foreground {
            let config = Config()
            print("Starting in foreground mode (Ctrl+C to stop)...")
            print("Watching: \(config.watch.joined(separator: ", "))")
            print("Output: \(config.outputDir)")
            let tracker = Tracker(config: config)
            tracker.run()
        } else {
            guard FileManager.default.fileExists(atPath: Paths.launchdPlist.path) else {
                print("Error: Launchd plist not found. Run 'recent-work init' first.")
                throw ExitCode.failure
            }
            let result = shell("launchctl", "load", "-w", Paths.launchdPlist.path)
            if result == 0 {
                print("Started recent-work daemon.")
            } else {
                print("Failed to start daemon. It may already be running (check 'recent-work status').")
            }
        }
    }
}

// MARK: - Stop

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop the file watcher daemon."
    )

    func run() throws {
        let result = shell("launchctl", "unload", Paths.launchdPlist.path)
        if result == 0 {
            print("Stopped recent-work daemon.")
        } else {
            print("Failed to stop daemon. It may not be running.")
        }
    }
}

// MARK: - Status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show daemon status, file count, and watched directories."
    )

    func run() throws {
        let config = Config()

        let isRunning = isDaemonRunning()
        print("Daemon: \(isRunning ? "running" : "stopped")")

        let stateStore = StateStore(outputDir: config.outputURL)
        stateStore.load()
        let entries = stateStore.allEntries()
        print("Tracked files: \(entries.count) / \(config.retention.maxFiles) max")
        print("Max age: \(config.retention.maxAgeHours) hours")

        print("\nWatched directories:")
        for dir in config.watch {
            let expanded = (dir as NSString).expandingTildeInPath
            let exists = FileManager.default.fileExists(atPath: expanded)
            print("  \(exists ? "✓" : "✗") \(dir)")
        }

        print("\nOutput: \(config.outputDir)")
    }
}

// MARK: - List

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List current symlinks and their targets."
    )

    func run() throws {
        let config = Config()
        let stateStore = StateStore(outputDir: config.outputURL)
        stateStore.load()

        let sorted = stateStore.sortedByAge().reversed()
        if sorted.isEmpty {
            print("No tracked files.")
            return
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        for (name, entry) in sorted {
            let age = formatter.localizedString(for: entry.timestamp, relativeTo: Date())
            let broken = !FileManager.default.fileExists(atPath: entry.originalPath)
            let status = broken ? " [broken]" : ""
            print("\(name)\(status)")
            print("  → \(entry.originalPath)  (\(age))")
        }
        print("\n\(sorted.count) file(s)")
    }
}

// MARK: - Clear

struct Clear: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove all symlinks and reset state."
    )

    @Flag(name: .long, help: "Skip confirmation prompt")
    var yes = false

    func run() throws {
        let config = Config()
        let stateStore = StateStore(outputDir: config.outputURL)
        stateStore.load()

        let count = stateStore.allEntries().count
        if count == 0 {
            print("No tracked files to clear.")
            return
        }

        if !yes {
            print("Remove \(count) symlink(s) from \(config.outputURL.path)? [y/N] ", terminator: "")
            guard let answer = readLine(), answer.lowercased().hasPrefix("y") else {
                print("Cancelled.")
                return
            }
        }

        let manager = SymlinkManager(
            outputDir: config.outputURL,
            stateStore: stateStore
        )
        manager.removeAll()
        print("Cleared all symlinks.")
    }
}

// MARK: - Uninstall

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop daemon, remove plist, and optionally remove the managed directory."
    )

    @Flag(name: .long, help: "Skip confirmation prompt")
    var yes = false

    func run() throws {
        let config = Config()
        let fm = FileManager.default

        if !yes {
            print("This will:")
            print("  - Stop the daemon")
            print("  - Remove the launchd plist")
            print("  - Remove managed directory (\(config.outputURL.path))")
            print("\nContinue? [y/N] ", terminator: "")
            guard let answer = readLine(), answer.lowercased().hasPrefix("y") else {
                print("Cancelled.")
                return
            }
        }

        // Stop daemon
        _ = shell("launchctl", "unload", Paths.launchdPlist.path)
        print("Stopped daemon.")

        // Remove plist
        if fm.fileExists(atPath: Paths.launchdPlist.path) {
            try fm.removeItem(at: Paths.launchdPlist)
            print("Removed launchd plist.")
        }

        // Remove managed directory
        if fm.fileExists(atPath: config.outputURL.path) {
            try fm.removeItem(at: config.outputURL)
            print("Removed managed directory.")
        }

        // Remove log directory
        if fm.fileExists(atPath: Paths.logDir.path) {
            try fm.removeItem(at: Paths.logDir)
            print("Removed log directory.")
        }

        print("\nUninstall complete.")
    }
}

// MARK: - Helpers

@discardableResult
private func shell(_ args: String...) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}

private func isDaemonRunning() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["list", Paths.launchdLabel]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

private func generateLaunchdPlist() -> String {
    let binaryPath: String
    let currentExec = ProcessInfo.processInfo.arguments[0]
    if currentExec.contains("/.build/") {
        binaryPath = "/usr/local/bin/recent-work"
    } else {
        binaryPath = currentExec
    }

    let logDir = Paths.logDir.path
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(Paths.launchdLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(binaryPath)</string>
            <string>start</string>
            <string>--foreground</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>\(logDir)/recent-work.log</string>
        <key>StandardErrorPath</key>
        <string>\(logDir)/recent-work.err</string>
    </dict>
    </plist>
    """
}

private func pinToFinderSidebar(url: URL) {
    let script = """
    tell application "Finder"
        try
            make new item at end of favorites sidebar list with properties {item:POSIX file "\(url.path)" as alias}
        end try
    end tell
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            print("Pinned \(url.path) to Finder sidebar.")
        }
    } catch {
        // Non-fatal — user can add manually
    }
}
