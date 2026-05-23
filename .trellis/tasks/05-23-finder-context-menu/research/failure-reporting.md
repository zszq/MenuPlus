# 失败回报方案

**目的**：主 App 异步执行 Extension 委托的动作时，失败如何告知用户。

## 一、约束

- Extension（`LSPlugInKitProxy` 进程）**不能**用 `UNUserNotificationCenter`，会抛 `NSInternalInconsistencyException`（这是项目里已经踩过的坑，见 `FinderExt/FinderSyncActions.swift:7-10` 的注释）
- Extension 也不能直接弹 `NSAlert`（菜单运行环境，弹窗体验差且可能被忽略）
- 主 App **可以**用 `UNUserNotificationCenter` 和 `NSAlert`
- 失败信息要在用户能看到的合理时机出现（不是埋在 Console.app 里）

## 二、方案对比

| 方案 | 用户感知 | 实现难度 | 干扰程度 |
|---|---|---|---|
| **A. 主 App 弹 `UNUserNotificationCenter` 通知** | 强（系统通知中心） | 低 | 中（通知会停留几秒） |
| **B. 主 App 弹 `NSAlert` 模态** | 极强（阻塞） | 极低 | 高（打断流程） |
| **C. 写状态到共享文件 + 菜单栏图标变色** | 弱（用户得主动看菜单栏） | 中 | 低 |
| **D. 双向 Darwin Notif + Extension 端再 NSLog** | 无（用户看不到） | 低 | 零（实际等于没回报） |
| **E. 主 App 把失败累积，弹一个"最近一次失败"红点 / 列表** | 中 | 中 | 低 |

## 三、推荐：**A + E 组合**

### A：单次失败立即用 `UNUserNotificationCenter`

```swift
// 主 App
import UserNotifications

enum FailureNotifier {
    static func requestAuthIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted { NSLog("[rightMenu] 用户拒绝通知权限") }
        }
    }

    static func show(message: String, title: String = "rightMenu 操作失败") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // 立即触发
        )
        UNUserNotificationCenter.current().add(req)
    }
}
```

**注意事项**：
1. 首次启动主 App 时必须 `requestAuthorization`，否则通知不显示
2. 主 App 的 Info.plist 已经有 `NSUserNotificationUsageDescription`（见 `rightMenu/Info.plist:7-8`），✅
3. 用户在 macOS 通知设置中可以关掉，这是用户自由

### E：菜单栏列表保留最近 N 次失败

在主 App 的 `MenuBarView` 里加一节"最近失败"。点击可以重试或忽略。

```swift
struct MenuBarView: View {
    @State private var recentFailures: [IPCResponse] = FailureStore.load()

    var body: some View {
        // 现有内容...

        if !recentFailures.isEmpty {
            Divider()
            Menu("最近失败 (\(recentFailures.count))") {
                ForEach(recentFailures, id: \.requestId) { r in
                    Button("\(r.errorMessage ?? "未知")") {
                        // 可选：点击复制错误到剪贴板
                    }
                }
                Divider()
                Button("清空") { FailureStore.clear(); recentFailures = [] }
            }
        }
    }
}
```

`FailureStore` 用 `UserDefaults(suiteName: "group.zl.rightMenu")` 持久化最近 10 条失败。

## 四、为什么 D（双向 Darwin Notif 回报到 Extension）不行

- Extension 收到失败 Darwin Notif 后**什么也做不了**：
  - 不能弹通知（NSInternalInconsistencyException）
  - 不能弹 NSAlert（菜单生命周期，可能此时菜单已关闭）
  - 只能 NSLog → 等于没回报
- **不要走这条路**

## 五、错误分类

主 App 执行失败的典型分类，决定通知文案：

| 类别 | 例子 | 推荐文案 |
|---|---|---|
| 目标 App 未安装 | VSCode 未装 | "未找到 Visual Studio Code，请先安装" |
| 目标 App 启动失败 | Terminal.app 损坏 | "无法打开终端：\(error.localizedDescription)" |
| 文件操作失败 | 目录无写权限 | "无法在 \(path) 创建文件：权限不足" |
| 系统命令失败 | killall Finder 没装 | "重启访达失败：\(reason)" |
| 未知错误 | bug | "操作失败：\(error.localizedDescription)" |

## 六、与现有 NSLog 的关系

现有 `FinderExt/FinderSyncActions.swift` 大量用 NSLog 写错误（见 8 处 `NSLog("[rightMenu] ..."`）。
改造后这些 NSLog **保留在 Extension 端**（作为最后兜底），但**用户面向的回报全部迁移到主 App 端**。

新分工：
- Extension：只 NSLog "IPC 请求已发送" / "App Group 不可用，降级到 URL Scheme"
- 主 App：执行失败 → `FailureNotifier.show()`  + 写入 `FailureStore`

## 七、风险

| 风险 | 缓解 |
|---|---|
| 用户禁用了 macOS 通知 | 菜单栏失败列表（方案 E）兜底 |
| 失败发生在主 App 启动瞬间，通知权限还没拿到 | 启动时第一时间 `requestAuthorization`；如果尚未授权，存到 FailureStore 等用户看菜单 |
| 通知文案太长被截断 | 控制在 100 字以内，细节走 FailureStore |
| 主 App 退出时未处理的失败丢失 | FailureStore 用 UserDefaults 持久化 |

## 引用

- Apple Doc: `UNUserNotificationCenter`, `UNMutableNotificationContent`
- 当前仓库 `rightMenu/Info.plist:7-8` — `NSUserNotificationUsageDescription` 已有
- 当前仓库 `FinderExt/FinderSyncActions.swift:7-10` — Extension 不能用 UN 的踩坑注释
