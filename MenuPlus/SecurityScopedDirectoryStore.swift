import AppKit

enum SecurityScopedDirectoryStore {
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
            if let bookmarkedURL = try resolveBookmark(for: standardizedDirectoryPath),
               try performWithSecurityScope(for: bookmarkedURL, originalPath: standardizedDirectoryPath, perform: perform) {
                return
            }
        } catch {
            NSLog("[MenuPlus/MainApp] 读取 bookmark 失败，准备回退到重新授权：%@, error=%@", standardizedDirectoryPath, error.localizedDescription)
            try resetBookmarkStore()
        }

        NSLog("[MenuPlus/MainApp] 未命中可用 bookmark，准备请求目录授权：%@", standardizedDirectoryPath)
        let grantedURL = try requestDirectoryAccess(for: standardizedDirectoryPath, actionName: actionName)
        try saveBookmark(for: grantedURL)

        guard try performWithSecurityScope(
            for: grantedURL,
            originalPath: standardizedDirectoryPath,
            perform: perform
        ) else {
            throw AccessError.securityScopeActivationFailed(path: standardizedDirectoryPath)
        }
    }

    private static func performWithSecurityScope(
        for directoryURL: URL,
        originalPath: String,
        perform: (URL) throws -> Void
    ) throws -> Bool {
        let started = directoryURL.startAccessingSecurityScopedResource()
        guard started else {
            NSLog("[MenuPlus/MainApp] startAccessingSecurityScopedResource 失败：%@", directoryURL.path)
            removeBookmark(for: originalPath)
            return false
        }

        defer {
            directoryURL.stopAccessingSecurityScopedResource()
        }

        try perform(directoryURL)
        return true
    }

    private static func resolveBookmark(for standardizedDirectoryPath: String) throws -> URL? {
        let store = try bookmarkStore()
        guard let bookmark = store[standardizedDirectoryPath] else {
            NSLog("[MenuPlus/MainApp] 未找到 bookmark：%@", standardizedDirectoryPath)
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                NSLog("[MenuPlus/MainApp] bookmark 已过期，准备刷新：%@", standardizedDirectoryPath)
                try saveBookmark(for: url)
            } else {
                NSLog("[MenuPlus/MainApp] 已复用 bookmark：%@", standardizedDirectoryPath)
            }

            return url
        } catch {
            NSLog("[MenuPlus/MainApp] 解析 bookmark 失败：%@, error=%@", standardizedDirectoryPath, error.localizedDescription)
            removeBookmark(for: standardizedDirectoryPath)
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
}
