import Foundation

public class FileWatcher {
    private let path: String
    private let callback: () -> Void
    private var streamRef: FSEventStreamRef?

    public init(path: String, callback: @escaping () -> Void) {
        self.path = path
        self.callback = callback
    }

    public func start() {
        let pathsToWatch = ["\(path)/.beads"] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, eventFlags, eventIds in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.callback()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagFileEvents)
        )

        guard let streamRef = streamRef else { return }

        FSEventStreamScheduleWithRunLoop(streamRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(streamRef)
    }

    public func stop() {
        guard let streamRef = streamRef else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
    }
}
