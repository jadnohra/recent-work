import Foundation
import os

public final class Tracker: @unchecked Sendable {
    private let config: Config
    private let stateStore: StateStore
    private let symlinkManager: SymlinkManager
    private let pruner: Pruner
    private var watcher: Watcher?
    private let logger = Logger(subsystem: "com.recentwork", category: "Tracker")

    public init(config: Config) {
        self.config = config
        self.stateStore = StateStore(outputDir: config.outputURL)
        self.symlinkManager = SymlinkManager(
            outputDir: config.outputURL,
            stateStore: stateStore
        )
        self.pruner = Pruner(
            outputDir: config.outputURL,
            stateStore: stateStore,
            maxFiles: config.retention.maxFiles,
            maxAgeHours: config.retention.maxAgeHours
        )
    }

    /// Start watching and processing events. Blocks on RunLoop.
    public func run() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: config.outputURL, withIntermediateDirectories: true)
            try fm.createDirectory(
                at: Paths.stateDir(outputDir: config.outputURL),
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create output directories: \(error.localizedDescription)")
            return
        }

        stateStore.load()
        pruner.prune()

        let validWatchDirs = config.watchURLs.filter { url in
            var isDir: ObjCBool = true
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if !exists || !isDir.boolValue {
                logger.warning("Watch directory does not exist: \(url.path)")
            }
            return exists && isDir.boolValue
        }

        guard !validWatchDirs.isEmpty else {
            logger.error("No valid watch directories found")
            return
        }

        setupSignalHandlers()

        watcher = Watcher(
            directories: validWatchDirs,
            debounceInterval: config.debounceSeconds,
            outputDir: config.outputURL
        ) { [weak self] url in
            self?.handleEvent(url: url)
        }
        watcher?.start()

        pruner.startPeriodicPruning(interval: 60)

        logger.info("Tracker started — watching \(validWatchDirs.count) directories, output: \(self.config.outputURL.path)")

        RunLoop.current.run()
    }

    public func stop() {
        watcher?.stop()
        pruner.stopPeriodicPruning()
        logger.info("Tracker stopped")
    }

    // MARK: - Event handling

    private func handleEvent(url: URL) {
        let path = url.path

        // Skip hidden directories anywhere in path
        for component in url.pathComponents {
            if component.hasPrefix(".") && component != "/" {
                return
            }
        }

        // Skip ~/Library and ~/.Trash
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix("\(home)/Library/") || path.hasPrefix("\(home)/.Trash/") {
            return
        }

        symlinkManager.createSymlink(for: url)
        pruner.prune()
    }

    // MARK: - Signal handling

    private func setupSignalHandlers() {
        let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signalSource.setEventHandler { [weak self] in
            self?.logger.info("Received SIGTERM, shutting down")
            self?.stop()
            exit(0)
        }
        signalSource.resume()
        signal(SIGTERM, SIG_IGN)

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler { [weak self] in
            self?.logger.info("Received SIGINT, shutting down")
            self?.stop()
            exit(0)
        }
        intSource.resume()
        signal(SIGINT, SIG_IGN)

        _signalSources = [signalSource, intSource]
    }

    private var _signalSources: [Any] = []
}
