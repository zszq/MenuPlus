# macOS Finder 右键菜单扩展

## Goal

为 rightMenu macOS 应用添加 Finder Sync Extension，让用户在访达中右键点击文件/文件夹时看到自定义菜单，提升开发效率。主 App 以菜单栏图标形式常驻，支持开机自启。

## Requirements

### 主 App（菜单栏）
* 无 Dock 图标（`LSUIElement = YES`）
* 菜单栏图标，点击展开菜单：
  * 启用/禁用 Finder 扩展（跳转系统偏好设置 → 扩展）
  * 开机启动开关（`SMAppService`）
  * 退出
* 首次启动引导用户在系统设置中启用 Finder 扩展

### Finder Sync Extension
* 注册监控目录：`/`（全盘，监控所有路径）
* 右键菜单以子菜单形式出现（菜单名：`rightMenu`）
* 按目标类型过滤显示菜单项：

| # | 动作 | 右键文件夹 | 右键文件 |
|---|------|-----------|---------|
| 1 | 在终端中打开 | ✅ | ❌ |
| 2 | 在 VSCode 中打开 | ✅ | ✅ |
| 3 | 复制完整路径 | ✅ | ✅ |
| 4 | 复制文件名 | ✅ | ✅ |
| 5 | 新建空白文件 | ✅ | ❌ |
| 6 | 新建 txt 文件 | ✅ | ❌ |
| 7 | 显示/隐藏隐藏文件 | ✅ | ✅ |
| 8 | 在新 Finder 窗口中打开 | ✅ | ❌ |

### 各动作实现细节
* **在终端中打开**：`NSWorkspace` 打开 Terminal.app，AppleScript 传入目标路径
* **在 VSCode 中打开**：`NSWorkspace` 打开 `vscode://file/<path>`，VSCode 未安装则系统通知提示
* **复制完整路径**：写入 `NSPasteboard.general`
* **复制文件名**：`URL.lastPathComponent` 写入剪贴板
* **新建空白文件**：`FileManager.createFile`，冲突时自动加数字后缀（`新建文件 2`）
* **新建 txt 文件**：同上，后缀 `.txt`
* **显示/隐藏隐藏文件**：`defaults write com.apple.finder AppleShowAllFiles` + `killall Finder`
* **在新 Finder 窗口中打开**：`NSWorkspace.open` 打开文件夹 URL

## Acceptance Criteria

* [ ] 在访达右键文件夹，能看到 `rightMenu` 子菜单，包含全部 8 个动作
* [ ] 在访达右键文件，只显示动作 2、3、4、7
* [ ] 在终端中打开 → Terminal.app 在对应目录启动
* [ ] 在 VSCode 中打开 → VSCode 打开对应路径；未安装时弹出通知
* [ ] 复制路径 / 文件名 → 剪贴板内容正确
* [ ] 新建文件 / txt → 文件出现在目标文件夹，重名时自动加后缀
* [ ] 切换隐藏文件 → Finder 重启后状态生效
* [ ] 菜单栏图标可用，开机启动开关正常工作
* [ ] 主 App 无 Dock 图标

## Definition of Done

* 在真机 macOS 13+ 上可正常启用 Extension
* 所有菜单动作在真机验证通过
* 无 sandbox / entitlement 相关崩溃

## Technical Approach

* **Finder Sync Extension Target**：新增 Extension target，`FIFinderSync` 子类实现 `menu(for:)` 和 `beginObservingDirectory(at:)`
* **分发方式**：直接分发（非 App Store），禁用 App Sandbox 或使用宽松 entitlement
* **开机启动**：`SMAppService.mainApp.register()` / `.unregister()`（macOS 13+）
* **主 App ↔ Extension 通信**：MVP 阶段无需通信（固定菜单），Phase 2 再引入 App Group / UserDefaults(suiteName)
* **最低系统版本**：macOS 13 Ventura

## Decision (ADR-lite)

| 决策 | 选择 | 理由 |
|------|------|------|
| 菜单项可配置性 | 两阶段（MVP 固定，Phase 2 可配置） | 快速交付，复杂度可控 |
| 主 App 形态 | 菜单栏图标，无 Dock | 轻量无打扰 |
| 终端 | Terminal.app | 无需额外安装 |
| 文件 vs 文件夹 | 按类型过滤显示 | 避免无意义动作出现 |
| 分发 | 直接分发优先 | sandbox 限制少，开发快 |
| 开机启动 | 纳入 MVP | 体验完整，SMAppService 简单 |

## Out of Scope (MVP)

* iTerm2 / 其他终端支持
* 用户自定义菜单项（Phase 2）
* App Store 上架（后续）
* 右键文件时操作父文件夹的动作
* Git 相关动作

## Technical Notes

* FinderSync 文档：https://developer.apple.com/documentation/findersync
* Extension Bundle ID 示例：`com.zl.rightMenu.FinderExt`
* App Group ID（Phase 2 预留）：`group.com.zl.rightMenu`
* SMAppService 需 macOS 13+，Info.plist 注册 `SMLoginItemAgentType`
* 项目当前仅有 SwiftUI 模板文件，需新增 Extension target 和改造主 App
