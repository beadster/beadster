import Foundation

public class FileWatcher {
    private let path: String
    private let callback: () -> Void
    private let latency: CFTimeInterval
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.beadster.filewatcher")

    public init(path: String, latency: CFTimeInterval = 1.0, callback: @escaping () -> Void) {
        self.path = path
        self.latency = latency
        self.callback = callback
    }

    public func start() {
        let pathsToWatch = [path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        streamRef = FSEventStreamCreate(
            nil,
            { (streamRef, contextInfo, numEvents, eventPaths, eventFlags, eventIds) in
                let watcher = Unmanaged<FileWatcher>.fromOpaque(contextInfo!).takeUnretainedValue()
                watcher.callback()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )

        guard let streamRef = streamRef else { return }

        // Use modern dispatch queue API instead of deprecated run loop
        FSEventStreamSetDispatchQueue(streamRef, queue)
        FSEventStreamStart(streamRef)
    }

    public func stop() {
        guard let streamRef = streamRef else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
        self.streamRef = nil
    }

    deinit {
        stop()
    }
}
