import AppKit

enum SecurityScopedDirectoryStore {
    private struct ResolvedBookmarkMatch {
        let bookmarkPath: String
        let bookmarkedURL: URL
    }

    private enum AccessError: LocalizedError {
        case cancelled(actionName: String)
        case wrongDirectory(expectedPath: String)
        case bookmarkStoreCorrupted
        case securityScopeActivationFailed(path: String)

        var errorDescription: String? {
            switch self {
            case .cancelled(let actionName):
                return "已取消“\(actionName)”的目录授权。下次再次执行时会重新弹出授权面板。"
            case .wrongDirectory(let expectedPath):
                return "请在授权面板中选择当前目录本身：\(expectedPath)"
            case .bookmarkStoreCorrupted:
                return "目录授权缓存已损坏，已无法读取，请重新授权。"
            case .securityScopeActivationFailed(let path):
                return "系统暂时无法激活目录授权：\(path)。请重试一次；若仍失败，请重新授权。"
            }
        }
    }

    private static let bookmarkStoreDefaultsKey = "securityScopedBookmarks"

    static func withAccess(
        to directoryPath: String,
        actionName: String,
        perform: (URL) throws -> Void
    ) throws {
        let standardizedDirectoryPath = standardizedPath(for: directoryPath)

        do {
            if let bookmarkMatch = try resolveBestBookmark(for: standardizedDirectoryPath),
               try performWithSecurityScope(
                using: bookmarkMatch,
                targetPath: standardizedDirectoryPath,
                perform: perform
               ) {
                return
            }
        } catch AccessError.bookmarkStoreCorrupted {
            NSLog("[MenuPlus/MainApp] bookmark store 损坏，准备清空后重新授权")
            try resetBookmarkStore()
        } catch {
            NSLog("[MenuPlus/MainApp] 复用 bookmark 失败，准备回退到重新授权：%@, error=%@", standardizedDirectoryPath, error.localizedDescription)
        }

        NSLog("[MenuPlus/MainApp] 未命中可用 bookmark，准备请求目录授权：%@", standardizedDirectoryPath)
        let grantedURL = try requestDirectoryAccess(for: standardizedDirectoryPath, actionName: actionName)
        try saveBookmark(for: grantedURL)

        guard try performWithSecurityScope(
            using: ResolvedBookmarkMatch(
                bookmarkPath: standardizedPath(for: grantedURL.path),
                bookmarkedURL: grantedURL
            ),
            targetPath: standardizedDirectoryPath,
            perform: perform
        ) else {
            throw AccessError.securityScopeActivationFailed(path: standardizedDirectoryPath)
        }
    }

    static func authorizedDirectoryPaths() throws -> [String] {
        Array(try bookmarkStore().keys).sorted()
    }

    @discardableResult
    static func authorizeDirectoriesFromSettings() throws -> Bool {
        let selectedURLs = requestDirectoriesForSettings()
        guard !selectedURLs.isEmpty else {
            return false
        }

        for url in selectedURLs {
            try saveBookmark(for: url)
        }

        return true
    }

    static func removeAuthorizedDirectories(_ directoryPaths: [String]) throws {
        guard !directoryPaths.isEmpty else {
            return
        }

        var store = try bookmarkStore()
        for directoryPath in directoryPaths {
            store.removeValue(forKey: standardizedPath(for: directoryPath))
        }
        try persistBookmarkStore(store)
    }

    private static func performWithSecurityScope(
        using bookmarkMatch: ResolvedBookmarkMatch,
        targetPath: String,
        perform: (URL) throws -> Void
    ) throws -> Bool {
        let directoryURL = bookmarkMatch.bookmarkedURL
        let started = directoryURL.startAccessingSecurityScopedResource()
        guard started else {
            NSLog("[MenuPlus/MainApp] startAccessingSecurityScopedResource 失败：%@", directoryURL.path)
            removeBookmark(for: bookmarkMatch.bookmarkPath)
            return false
        }

        defer {
            directoryURL.stopAccessingSecurityScopedResource()
        }

        try perform(scopedURL(for: targetPath, using: bookmarkMatch))
        return true
    }

    private static func resolveBestBookmark(for standardizedDirectoryPath: String) throws -> ResolvedBookmarkMatch? {
        let store = try bookmarkStore()
        let matchingPaths = store.keys
            .filter { bookmarkPath in
                standardizedDirectoryPath == bookmarkPath
                    || standardizedDirectoryPath.hasPrefix(bookmarkPath + "/")
            }
            .sorted { $0.count > $1.count }

        guard !matchingPaths.isEmpty else {
            NSLog("[MenuPlus/MainApp] 未找到可复用 bookmark：%@", standardizedDirectoryPath)
            return nil
        }

        for bookmarkPath in matchingPaths {
            guard let bookmark = store[bookmarkPath] else {
                continue
            }

            guard let url = try resolveBookmark(for: bookmarkPath, bookmarkData: bookmark) else {
                continue
            }

            NSLog(
                "[MenuPlus/MainApp] 已复用 bookmark：target=%@, bookmark=%@",
                standardizedDirectoryPath,
                bookmarkPath
            )
            return ResolvedBookmarkMatch(bookmarkPath: bookmarkPath, bookmarkedURL: url)
        }

        return nil
    }

    private static func resolveBookmark(for bookmarkPath: String, bookmarkData: Data) throws -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                NSLog("[MenuPlus/MainApp] bookmark 已过期，准备刷新：%@", bookmarkPath)
                try saveBookmark(for: url)
            }

            return url
        } catch {
            NSLog("[MenuPlus/MainApp] 解析 bookmark 失败：%@, error=%@", bookmarkPath, error.localizedDescription)
            removeBookmark(for: bookmarkPath)
            return nil
        }
    }

    private static func requestDirectoryAccess(for directoryPath: String, actionName: String) throws -> URL {
        if Thread.isMainThread {
            return try requestDirectoryAccessOnMain(for: directoryPath, actionName: actionName)
        }

        return try DispatchQueue.main.sync {
            try requestDirectoryAccessOnMain(for: directoryPath, actionName: actionName)
        }
    }

    private static func requestDirectoryAccessOnMain(for directoryPath: String, actionName: String) throws -> URL {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: directoryPath)
        panel.message = """
        \(actionName) 需要你显式授权当前 Finder 目录的访问权限。

        请在面板中选中这个目录：
        \(directoryPath)
        """
        panel.prompt = "授权此目录"

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            throw AccessError.cancelled(actionName: actionName)
        }

        let targetPath = standardizedPath(for: directoryPath)
        let selectedPath = standardizedPath(for: selectedURL.path)
        guard selectedPath == targetPath else {
            throw AccessError.wrongDirectory(expectedPath: directoryPath)
        }

        return selectedURL
    }

    private static func requestDirectoriesForSettings() -> [URL] {
        if Thread.isMainThread {
            return requestDirectoriesForSettingsOnMain()
        }

        return DispatchQueue.main.sync {
            requestDirectoriesForSettingsOnMain()
        }
    }

    private static func requestDirectoriesForSettingsOnMain() -> [URL] {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = """
        选择要预授权的目录。

        已授权目录下的所有子目录都会自动复用，无需再次授权。
        """
        panel.prompt = "添加授权目录"

        guard panel.runModal() == .OK else {
            return []
        }

        return panel.urls
    }

    private static func saveBookmark(for url: URL) throws {
        let standardized = standardizedPath(for: url.path)
        let data: Data

        do {
            data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
            )
        } catch {
            NSLog("[MenuPlus/MainApp] 创建 bookmark 失败：%@, error=%@", standardized, error.localizedDescription)
            throw error
        }

        var store = try bookmarkStore()
        store[standardized] = data
        try persistBookmarkStore(store)
        NSLog("[MenuPlus/MainApp] 已保存 bookmark：%@", standardized)
    }

    private static func removeBookmark(for directoryPath: String) {
        let standardized = standardizedPath(for: directoryPath)

        do {
            var store = try bookmarkStore()
            store.removeValue(forKey: standardized)
            try persistBookmarkStore(store)
            NSLog("[MenuPlus/MainApp] 已移除失效 bookmark：%@", standardized)
        } catch {
            NSLog("[MenuPlus/MainApp] 移除 bookmark 失败：%@, error=%@", standardized, error.localizedDescription)
        }
    }

    private static func bookmarkStore() throws -> [String: Data] {
        let defaults = UserDefaults.standard
        guard let store = defaults.dictionary(forKey: bookmarkStoreDefaultsKey) else {
            NSLog("[MenuPlus/MainApp] bookmark store 为空")
            return [:]
        }

        var result: [String: Data] = [:]
        for (key, value) in store {
            guard let data = value as? Data else {
                NSLog("[MenuPlus/MainApp] bookmark store 格式损坏，key=%@", key)
                throw AccessError.bookmarkStoreCorrupted
            }
            result[key] = data
        }

        NSLog("[MenuPlus/MainApp] 已加载 bookmark store，count=%d", result.count)
        return result
    }

    private static func persistBookmarkStore(_ store: [String: Data]) throws {
        UserDefaults.standard.set(store, forKey: bookmarkStoreDefaultsKey)
        NSLog("[MenuPlus/MainApp] 已写入 bookmark store，count=%d", store.count)
    }

    private static func resetBookmarkStore() throws {
        try persistBookmarkStore([:])
    }

    private static func standardizedPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func scopedURL(for targetPath: String, using bookmarkMatch: ResolvedBookmarkMatch) -> URL {
        guard targetPath != bookmarkMatch.bookmarkPath else {
            return bookmarkMatch.bookmarkedURL
        }

        let targetComponents = URL(fileURLWithPath: targetPath).standardizedFileURL.pathComponents
        let bookmarkComponents = URL(fileURLWithPath: bookmarkMatch.bookmarkPath).standardizedFileURL.pathComponents
        let relativeComponents = targetComponents.dropFirst(bookmarkComponents.count)

        return relativeComponents.reduce(bookmarkMatch.bookmarkedURL) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: true)
        }
    }
}
