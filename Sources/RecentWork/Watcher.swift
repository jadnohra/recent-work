import CoreServices
import Foundation
import os

public final class Watcher: @unchecked Sendable {
    public typealias EventHandler = (URL) -> Void

    private let directories: [String]
    private let debounceInterval: TimeInterval
    private let outputDir: URL
    private let handler: EventHandler
    private let logger = Logger(subsystem: "com.recentwork", category: "Watcher")

    private var stream: FSEventStreamRef?
    private var debounceTimers: [String: DispatchWorkItem] = [:]
    private let debounceQueue = DispatchQueue(label: "com.recentwork.debounce")

    public init(
        directories: [URL],
        debounceInterval: TimeInterval = 2.0,
        outputDir: URL,
        handler: @escaping EventHandler
    ) {
        self.directories = directories.map(\.path)
        self.debounceInterval = debounceInterval
        self.outputDir = outputDir
        self.handler = handler
    }

    public func start() {
        let pathsToWatch = directories as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagNoDefer)

        guard
            let stream = FSEventStreamCreate(
                nil,
                fsEventsCallback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.5,  // latency
                flags
            )
        else {
            logger.error("Failed to create FSEventStream")
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        logger.info("Watching \(self.directories.count) directories")
    }

    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        logger.info("Stopped watching")
    }

    // MARK: - Internal

    fileprivate func handleEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        for (path, flag) in zip(paths, flags) {
            let isFile = (flag & UInt32(kFSEventStreamEventFlagItemIsFile)) != 0
            let isCreated = (flag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
            let isModified = (flag & UInt32(kFSEventStreamEventFlagItemModified)) != 0
            let isRenamed = (flag & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
            let isRemoved = (flag & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0

            guard isFile, !isRemoved, (isCreated || isModified || isRenamed) else { continue }

            // Ignore events from the output directory
            let resolvedOutput = outputDir.standardizedFileURL.path
            if path.hasPrefix(resolvedOutput) { continue }

            debounce(path: path)
        }
    }

    private func debounce(path: String) {
        debounceQueue.async { [weak self] in
            guard let self else { return }

            // Cancel existing timer for this path
            self.debounceTimers[path]?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let url = URL(fileURLWithPath: path)

                // Verify file still exists
                guard FileManager.default.fileExists(atPath: path) else { return }

                self.handler(url)

                self.debounceQueue.async {
                    self.debounceTimers.removeValue(forKey: path)
                }
            }

            self.debounceTimers[path] = workItem
            self.debounceQueue.asyncAfter(
                deadline: .now() + self.debounceInterval,
                execute: workItem
            )
        }
    }
}

// MARK: - FSEvents C callback

private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()

    guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

    watcher.handleEvents(paths: cfPaths, flags: flags)
}
