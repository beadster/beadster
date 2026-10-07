// The folders the person granted, kept across launches: a bookmark per folder in
// BookmarkManager's store, the list of keys and saved paths in UserDefaults.
import AppKit
import BeadsKit
import BookmarkManager
import Foundation

@MainActor
@Observable
final class FolderList {
    private(set) var folders: [GrantedFolder] = []
    private let bookmarks = BookmarkManager()
    private let defaultsKey = "grantedFolders"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([GrantedFolder].self, from: data) {
            folders = saved
        }
    }

    /// The open panel: one folder (usually the one that holds every project). The bookmark is
    /// saved now; the folder joins the list only when the person confirms its projects (keep).
    func pick() -> GrantedFolder? {
        let key = "folder.\(UUID().uuidString)"
        guard let url = bookmarks.pickDirectory(forKey: key, message: "Choose the folder that holds your projects.", prompt: "Choose"),
              bookmarks.has(key: key) else { return nil }
        return GrantedFolder(key: key, path: url.path)
    }

    func keep(_ folder: GrantedFolder) {
        folders.append(folder)
        persist()
    }

    /// The sheet was cancelled: forget the bookmark the panel saved.
    func discard(_ folder: GrantedFolder) {
        bookmarks.remove(forKey: folder.key)
    }

    func remove(_ folder: GrantedFolder) {
        bookmarks.remove(forKey: folder.key)
        folders.removeAll { $0.key == folder.key }
        persist()
    }

    func health(of folder: GrantedFolder) -> GrantedFolder.Health {
        folder.health(resolvedPath: bookmarks.bookmarkedPath(forKey: folder.key))
    }

    /// Projects under a folder, scanned inside its security scope.
    func projects(in folder: GrantedFolder) -> [FoundProject] {
        bookmarks.withAccess(forKey: folder.key) { ProjectScanner.scan($0) } ?? []
    }

    func access(for folder: GrantedFolder) -> FolderAccess? {
        guard let data = UserDefaultsBookmarkStore().load(forKey: folder.key) else { return nil }
        return BookmarkAccess(bookmark: data)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
