# macOS 开发规范

> 本项目的 macOS 原生开发约定，覆盖 Finder Sync Extension、App Sandbox、Xcode 构建配置等关键领域。

---

## 规范索引

| 规范 | 说明 | 状态 |
|------|------|------|
| [Finder Sync Extension & IPC](./finder-sync-extension.md) | Sandbox 约束、URL Scheme IPC 架构、通知限制 | 已填写 |
| [Xcode 构建配置陷阱](./xcode-build-config.md) | Entitlements / Info.plist / ENABLE_APP_SANDBOX 等 Xcode 特有坑 | 已填写 |

---

## 速查：macOS 常见坑

1. **扩展进程不能用 `UNUserNotificationCenter`** → 见 finder-sync-extension.md
2. **`ENABLE_APP_SANDBOX` 构建设置会覆盖 entitlements 文件** → 见 xcode-build-config.md
3. **macOS Sequoia + ad-hoc 签名：关掉 sandbox 会导致 PluginKit 拒绝注册扩展** → 见 finder-sync-extension.md
4. **`GENERATE_INFOPLIST_FILE = NO` 时必须手动加 `CFBundleIdentifier`** → 见 xcode-build-config.md
5. **`selectedItemURLs()` 不自动授予 sandbox 的 NSWorkspace.open 权限** → 见 finder-sync-extension.md
