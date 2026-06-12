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
- codesign 报 `CFBundleIdentifier` 为 `MenuPlus`（使用了 CFBundleName 作为 fallback）而非 `zl.MenuPlus`
- Console 报 `Extension CFBundleVersion must match parent app (null)`
- FinderSync 扩展与主 App 的 bundle ID 父子关系验证失败

**最小必须加入主 App Info.plist 的内容**（以 MenuPlus 为例）：
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

主 App 注册 `menuplus://` scheme：

```xml
<!-- MenuPlus/Info.plist -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>zl.MenuPlus.scheme</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>menuplus</string>
        </array>
    </dict>
</array>
```

> 当前项目以 **App Sandbox = ON** 为主线，主 App 仍可作为 `menuplus://` 的 handler 接收 Finder 扩展的用户触发请求；这条路径更接近 Mac App Store 分发要求。
>
> 只有当动作需要额外 TCC（例如自动化控制 Finder）时，才由主 App 在收到 IPC 后继续触发系统授权或弹出操作指引。

## 5.1 主 App 目录授权需要 `ENABLE_USER_SELECTED_FILES = readwrite`

如果主 App 要通过 `NSOpenPanel` 获取目录授权，并保存 security-scoped bookmark 以支持 Finder 空白区域的“新建文件 / 新建 txt 文件”，则主 App target 必须在 `project.pbxproj` 里启用：

```pbxproj
ENABLE_USER_SELECTED_FILES = readwrite;
```

**验证**：
```bash
codesign -d --entitlements - path/to/MenuPlus.app
```

应看到：
```text
com.apple.security.files.user-selected.read-write = true
```

---

## 6. PluginKit 调试命令速查

```bash
# 查看已注册的 FinderSync 扩展
pluginkit -m -p com.apple.FinderSync -v

# 强制启用某个扩展（调试用）
pluginkit -e use -i zl.MenuPlus.FinderExt

# 重置扩展状态
pluginkit -e ignore -i zl.MenuPlus.FinderExt
pluginkit -e use -i zl.MenuPlus.FinderExt

# 重新注册 LaunchServices bundle
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f path/to/MenuPlus.app
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

## 8. AUTOMATION_APPLE_EVENTS 会静默注入 apple-events entitlement

**症状**：`.entitlements` 文件里没有 `com.apple.security.automation.apple-events`，但 `codesign -d --entitlements -` 显示签名中含有它。

**原因**：与 `ENABLE_APP_SANDBOX` 同机制——pbxproj 中 `AUTOMATION_APPLE_EVENTS = YES` 会在签名阶段自动注入该 entitlement，不经过 `.entitlements` 文件。

**为什么必须清理**：申请了但代码未使用的权限是 Mac App Store 常见拒审理由（最小权限原则）。本项目"在终端打开"已改走 `NSWorkspace.open(_:withApplicationAt:)`，全部代码零处使用 Apple Events（2026-06 整改时已 grep 确认并删除该设置）。

**验证**：
```bash
codesign -d --entitlements - path/to/MenuPlus.app | grep apple-events
# 无输出 = 已移除
```

---

## 9. 隐私清单 PrivacyInfo.xcprivacy（MAS 上传硬性要求）

自 2024-05-01 起，使用 required reason API 而未在隐私清单声明原因的应用会被 App Store Connect 拒收。

**本项目的声明**（`MenuPlus/PrivacyInfo.xcprivacy`）：

| 触发代码 | API 类别 | 原因码 |
|---------|---------|--------|
| `UserDefaults`（SecurityScopedDirectoryStore bookmark 缓存、AppRuntime 偏好） | `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1`（仅访问 App 自身写入的偏好） |

另含 `NSPrivacyTracking = false`、`NSPrivacyTrackingDomains = []`、`NSPrivacyCollectedDataTypes = []`。FinderExt 未使用任何 required reason API，无需单独清单。

**打包方式**：本项目两个 target 都是 `PBXFileSystemSynchronizedRootGroup`，把 `.xcprivacy` 放进 `MenuPlus/` 目录即自动进入 Copy Bundle Resources，**无需改 pbxproj**。

**验证**：
```bash
ls MenuPlus.app/Contents/Resources/PrivacyInfo.xcprivacy && plutil -lint 同路径
```

> **注意**：新增 UserDefaults 之外的 required reason API（如文件时间戳 `creationDate`、磁盘空间、系统启动时间）时，必须同步在清单中追加对应类别与原因码。

---

## 10. MAS 上传必备 Info.plist 键

`GENERATE_INFOPLIST_FILE = NO`（主 App）时以下键必须**手写**进 `MenuPlus/Info.plist`（参见 § 2 的 bundle keys，下面是 App Store 维度的补充）：

| Key | 值 | 缺失后果 |
|-----|----|---------|
| `LSApplicationCategoryType` | `public.app-category.utilities` | 上传报 ITMS-90242 |
| `ITSAppUsesNonExemptEncryption` | `false`（只用系统 HTTPS/无自定义加密） | 每次提交需手动回答出口合规问卷 |
| `NSHumanReadableCopyright` | 版权串 | 非强制，建议填写 |

FinderExt 走 `GENERATE_INFOPLIST_FILE = YES`，版权串由 `INFOPLIST_KEY_NSHumanReadableCopyright` 注入即可；分类与加密声明只需主 App 提供。

---

## 11. 常见构建错误速查

| 错误 / 症状 | 根因 | 修复 |
|------------|------|------|
| Bundle ID 显示为 `MenuPlus` 而非 `zl.MenuPlus` | Info.plist 缺少 `CFBundleIdentifier` | 加 `$(PRODUCT_BUNDLE_IDENTIFIER)` |
| 扩展注册失败 `-10811` | 重复 target 引用了不存在的 Info.plist | 在 Xcode 删除多余 target |
| 右键菜单消失（无报错） | 扩展 sandbox 被关闭 | 改回 `ENABLE_APP_SANDBOX = YES` |
| `app-sandbox` 修改无效 | Xcode build setting 覆盖 | 改 project.pbxproj 的 `ENABLE_APP_SANDBOX` |
| Copy Bundle Resources 警告 | Info.plist 被加入资源阶段 | 在 Build Phases 里删除它 |
| `CFBundleVersion must match parent app (null)` | 扩展 Info.plist 缺少版本 key | 加 `$(CURRENT_PROJECT_VERSION)` |
| 签名含 `automation.apple-events` 但代码没用 | pbxproj 残留 `AUTOMATION_APPLE_EVENTS = YES` | 删除该构建设置（见 § 8） |
| 上传报 ITMS-90242 | Info.plist 缺 `LSApplicationCategoryType` | 手写补键（见 § 10） |
| 上传报 ITMS-91053 / required reason API | 缺隐私清单或声明不全 | 补 `PrivacyInfo.xcprivacy`（见 § 9） |
