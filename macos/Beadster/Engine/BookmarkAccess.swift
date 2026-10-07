// A granted folder through its security-scoped bookmark (common BookmarkManager's resolve).
import BeadsKit
import BookmarkManager
import Foundation
import Synchronization

final class BookmarkAccess: FolderAccess {
    private let data: Data
    private let resolved = Mutex<URL?>(nil)

    init(bookmark data: Data) { self.data = data }

    func start() -> URL? {
        guard let (url, _) = BookmarkManager.resolve(data: data) else { return nil }
        resolved.withLock { $0 = url }
        return url
    }

    func stop() {
        resolved.withLock { url in
            url?.stopAccessingSecurityScopedResource()
            url = nil
        }
    }
}
