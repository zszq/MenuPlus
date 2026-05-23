# macOS Extension 开发思考清单

> 在为 FinderSync 扩展添加新功能之前，过一遍这份清单。

---

## 新增动作前

- [ ] 这个操作在沙盒内能直接执行吗？（写文件、启动外部 App → 不行）
  - 是 → 直接在扩展内用 `FinderSyncActions` 实现
  - 否 → 走 IPC（`IPCClient.send` + `IPCExecutor.execute`），见 [finder-sync-extension.md](../macos/finder-sync-extension.md)

- [ ] 是否涉及 `UNUserNotificationCenter`？
  - 扩展进程 → 绝对不能用，会立即崩溃
  - 主 App 进程 → 可用（已在 `applicationDidFinishLaunching` 申请权限）

- [ ] 新 `IPCAction` case 是否两个文件都更新了？
  - `FinderExt/IPCAction.swift` ✓
  - `rightMenu/IPCAction.swift` ✓（必须完全一致）

- [ ] `IPCExecutor.execute()` 的 `switch` 是否处理了新 case？

- [ ] 菜单显示条件是否合理？（参考 `allSelectedAreFolders` vs `hasFolder && !hasFile`）

---

## 修改 Xcode 构建配置前

- [ ] 要改 entitlement（沙盒/权限）？ → 改 `project.pbxproj` 的 `ENABLE_APP_SANDBOX`，不是只改 `.entitlements` 文件。见 [xcode-build-config.md](../macos/xcode-build-config.md) § 1。

- [ ] 要禁用扩展的沙盒？ → **不要这样做**，会导致 PluginKit 在 Sequoia/ad-hoc 下拒绝注册。

- [ ] 修改了 Info.plist？ → 确认所有 bundle key 都有正确的 `$(变量)` 占位符。

---

## 调试扩展不出现时

```bash
# 检查扩展是否被 PluginKit 识别
pluginkit -m -p com.apple.FinderSync -v

# 强制启用
pluginkit -e use -i zl.rightMenu.FinderExt

# 验证 entitlements 实际值
codesign -d --entitlements - path/to/rightMenu.app/Contents/PlugIns/FinderExt.appex
```
