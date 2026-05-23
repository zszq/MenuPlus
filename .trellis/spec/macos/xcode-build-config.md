# Xcode 构建配置陷阱

## 1. ENABLE_APP_SANDBOX 会覆盖 entitlements 文件

**症状**：修改了 `.entitlements` 文件中的 `app-sandbox` 为 `false`，但 `codesign -d --entitlements -` 显示仍为 `true`。

**原因**：Xcode 15+ 引入了 `ENABLE_APP_SANDBOX` 构建设置。当它被设为 `YES` 时，Xcode 在签名阶段自动将 `com.apple.security.app-sandbox = true` 注入 entitlements，**覆盖** `.entitlements` 文件里的值。

**解决**：必须修改 `project.pbxproj` 中的构建设置，而不是 entitlements 文件：

```
// project.pbxproj — Debug + Release 配置都要改
ENABLE_APP_SANDBOX = NO;   // 关沙盒
// 或
ENABLE_APP_SANDBOX = YES;  // 开沙盒（默认）
```

**验证**：修改后重新构建，运行：
```bash
codesign -d --entitlements - path/to/YourApp.app/Contents/MacOS/YourApp
```
确认 `application-sandbox` 的值符合预期。

> **注意**：对 FinderSync 扩展，禁止设为 NO。见 finder-sync-extension.md § 4。

---

## 2. GENERATE_INFOPLIST_FILE = NO 时必须手动补齐 bundle keys

当 `GENERATE_INFOPLIST_FILE = NO`（项目使用自定义 Info.plist 文件），Xcode **不会**自动注入以下 bundle keys：

| Key | 正确值 |
|-----|--------|
| `CFBundleIdentifier` | `$(PRODUCT_BUNDLE_IDENTIFIER)` |
| `CFBundleExecutable` | `$(EXECUTABLE_NAME)` |
| `CFBundlePackageType` | `$(PRODUCT_BUNDLE_PACKAGE_TYPE)` |
| `CFBundleShortVersionString` | `$(MARKETING_VERSION)` |
| `CFBundleVersion` | `$(CURRENT_PROJECT_VERSION)` |
| `LSMinimumSystemVersion` | `$(MACOSX_DEPLOYMENT_TARGET)` |

**症状**：
- codesign 报 `CFBundleIdentifier` 为 `rightMenu`（使用了 CFBundleName 作为 fallback）而非 `zl.rightMenu`
- Console 报 `Extension CFBundleVersion must match parent app (null)`
- FinderSync 扩展与主 App 的 bundle ID 父子关系验证失败

**最小必须加入主 App Info.plist 的内容**（以 rightMenu 为例）：
```xml
<key>CFBundleIdentifier</key>
<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
<key>CFBundleExecutable</key>
<string>$(EXECUTABLE_NAME)</string>
<key>CFBundlePackageType</key>
<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
<key>CFBundleShortVersionString</key>
<string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
<key>LSMinimumSystemVersion</key>
<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
```

---

## 3. Info.plist 加入 Copy Bundle Resources 导致警告

**症状**：构建警告 `The Copy Bundle Resources build phase contains this target's Info.plist file`。

**原因**：Info.plist 应由 Xcode 处理阶段（Info.plist Processing）自动包含，不应重复加入 Copy Bundle Resources。

**解决**：在 Xcode 中 Target → Build Phases → Copy Bundle Resources 里删除 Info.plist 条目。

---

## 4. CFBundleVersion 父子 App 必须一致

FinderSync 扩展的 `CFBundleVersion` 必须与主 App 一致（Apple 要求）。统一使用 `$(CURRENT_PROJECT_VERSION)` 占位符即可，Xcode 会注入同一个值。

---

## 5. URL Scheme 注册（Info.plist）

主 App 注册 `rightmenu://` scheme：

```xml
<!-- rightMenu/Info.plist -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>zl.rightMenu.scheme</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>rightmenu</string>
        </array>
    </dict>
</array>
```

> 主 App 必须是**无沙盒**（`ENABLE_APP_SANDBOX = NO`）才能作为 IPC 执行端；`rightmenu://` 的 LaunchServices 调用在 ad-hoc 签名下不需要额外 entitlement。

---

## 6. PluginKit 调试命令速查

```bash
# 查看已注册的 FinderSync 扩展
pluginkit -m -p com.apple.FinderSync -v

# 强制启用某个扩展（调试用）
pluginkit -e use -i zl.rightMenu.FinderExt

# 重置扩展状态
pluginkit -e ignore -i zl.rightMenu.FinderExt
pluginkit -e use -i zl.rightMenu.FinderExt

# 重新注册 LaunchServices bundle
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f path/to/rightMenu.app
```

---

## 7. App Group 可行性（ad-hoc 签名）

Xcode 可能在 Capabilities UI 显示警告（"unable to process entitlement"), 但**运行时 App Group Container 在 ad-hoc 签名下是可用的**。

验证方式（Phase 0 测试已确认）：
```swift
// 主 App 或扩展内打印
print(FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.zl.rightMenu"
))
// 返回非 nil → 可用
```

当前项目因 URL Scheme 已满足需求，未启用 App Group；但如将来需要传递大 payload（>2KB），可切换到 App Group 文件队列方案（详见 `.trellis/tasks/05-23-finder-context-menu/research/recommendation.md`）。

---

## 8. 常见构建错误速查

| 错误 / 症状 | 根因 | 修复 |
|------------|------|------|
| Bundle ID 显示为 `rightMenu` 而非 `zl.rightMenu` | Info.plist 缺少 `CFBundleIdentifier` | 加 `$(PRODUCT_BUNDLE_IDENTIFIER)` |
| 扩展注册失败 `-10811` | 重复 target 引用了不存在的 Info.plist | 在 Xcode 删除多余 target |
| 右键菜单消失（无报错） | 扩展 sandbox 被关闭 | 改回 `ENABLE_APP_SANDBOX = YES` |
| `app-sandbox` 修改无效 | Xcode build setting 覆盖 | 改 project.pbxproj 的 `ENABLE_APP_SANDBOX` |
| Copy Bundle Resources 警告 | Info.plist 被加入资源阶段 | 在 Build Phases 里删除它 |
| `CFBundleVersion must match parent app (null)` | 扩展 Info.plist 缺少版本 key | 加 `$(CURRENT_PROJECT_VERSION)` |
