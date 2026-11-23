# GlideCut 1.0 — macOS 13.0+ 兼容性说明与验证记录

> 日期：2026-11-22 23:50
> 约束：**最低部署目标 macOS 13.0 Ventura**，支持 13.0 及以上全部系统版本。

---

## 一、核心配置（已完成并实测验证）

| 项 | 值 | 验证方式 |
|---|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | **13.0**（项目级 Debug + Release 共 2 处） | pbxproj 实查 |
| 产物 `LSMinimumSystemVersion` | **13.0** | `defaults read Info.plist` |
| 可执行文件 `LC_BUILD_VERSION` **minos** | **13.0** | `otool -l`（这是真正的运行时门槛） |
| SDK | MacOSX27.2（高版本 SDK 编译低版本目标，属正常做法） | 构建日志 |

**关键点**：`minos 13.0` 是硬指标——它决定二进制能否在 macOS 13 上加载。仅改 Info.plist 不够，必须确认 `LC_BUILD_VERSION.minos`。

---

## 二、发现的 macOS 14+ API 并已修复（用户警告的"无意引入新版要求"）

修改 Deployment Target 后，编译器立即暴露了 3 处隐藏的 macOS 14+ 依赖：

| 文件 | 原用法 | 最低版本 | 修复方案 |
|---|---|---|---|
| `GlideCutApp.swift:15` | `MenuBarView().environmentObject(...)` | **macOS 14.0** | 改为向 `MenuBarView`/`SettingsView` **显式传参**注入 `EventController` |
| `MenuBarView.swift:23` | `@Environment(\.openSettings)` | **macOS 14.0** | 改为 `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)`（macOS 13 可用，带 `showPreferencesWindow:` 回退） |
| `MenuBarView.swift` | `SettingsLink { }` | **macOS 14.0** | 同上（已弃用该方案） |
| `SettingsView.swift:17` | `Text(...).foregroundStyle(.secondary)` | **macOS 14.0** | 改为 `.foregroundColor(.secondary)`（macOS 10.15+） |

> 注：`@EnvironmentObject`（View 级）在 macOS 13 可用，但 `Scene.environmentObject` 是 14+，故整体改为显式传参，最稳。

---

## 三、当前代码用到的 API 全部兼容性核对

| API | 最低版本 | 结论 |
|---|---|---|
| `MenuBarExtra`（Scene） | **macOS 13.0** | ✅ 正好达标 |
| `menuBarExtraStyle(.menu)` | **macOS 13.0** | ✅ |
| `Settings`（Scene） | macOS 11.0 | ✅ |
| `LabeledContent` | **macOS 13.0** | ✅ |
| `formStyle(.grouped)` | **macOS 13.0** | ✅ |
| `Toggle` / `Button` / `Menu` / `Text` / `Image` | macOS 10.x~11 | ✅ |
| `foregroundColor` | macOS 10.15 | ✅ |
| `@ObservedObject` / `@State` / `Binding` | macOS 10.15 | ✅ |
| `NSApplicationDelegate` / `NSApplicationDelegateAdaptor` | macOS 11.0 | ✅ |
| `NSWorkspace.shared.frontmostApplication` | macOS 10.x | ✅ |
| `CGEvent.tapCreate` / `CGEventTap` | macOS 10.4+ | ✅ |
| `CGPreflightListenEventAccess` / `CGRequestListenEventAccess` | **macOS 10.15** | ✅ |
| `CFMachPortCreateRunLoopSource` / `CFRunLoop*` | macOS 10.x | ✅ |
| `SMAppService`（开机启动，第二阶段用） | **macOS 13.0** | ✅ 正好可用，无需降级 |

---

## 四、用户要求的专项兼容性核对

### 4.1 菜单栏 ✅
`MenuBarExtra`（macOS 13.0+）+ `LSUIElement=true`。macOS 13 起支持 SwiftUI 菜单栏场景，且已在本机实测图标渲染（像素差分证据）。

### 4.2 系统事件监听 ✅
`CGEventTapCreate` 为 macOS 10.4+，`CGPreflightListenEventAccess` 为 macOS 10.15+，均远低于 13.0，无版本风险。

### 4.3 辅助功能/输入监控授权 ✅
- 检查：`CGPreflightListenEventAccess()`（10.15+）
- 请求：`CGRequestListenEventAccess()`（10.15+）
- 均兼容 13.0。注意：TCC 授权在 13/14/15 上的**系统设置路径略有差异**（13 为"系统偏好设置 → 隐私与安全性 → 输入监控"），引导文案需按版本适配（第二阶段实现）。

### 4.4 开机启动 ✅（第二阶段实现）
推荐 `SMAppService.mainApp`——**macOS 13.0 起提供**，正好满足最低目标；默认关闭。

### 4.5 窗口管理 ✅
- 设置窗口用 SwiftUI `Settings` 场景（macOS 11+）
- 打开方式用 `showSettingsWindow:` selector（macOS 13+），带旧 selector 回退
- 不使用 `openSettings` / `SettingsLink`（均 14+）

---

## 五、编译与产物验证（实测）

| 验证 | 结果 |
|---|---|
| Debug 编译（target 13.0） | **BUILD SUCCEEDED** |
| Release 编译（target 13.0） | **BUILD SUCCEEDED** |
| GlideCutWheelProbe 编译 | **BUILD SUCCEEDED** |
| Release 产物实际启动 | ✅ 成功（进程正常，日志写入） |
| `LSMinimumSystemVersion` | **13.0** |
| `otool LC_BUILD_VERSION minos` | **13.0** |
| dmg 完整性 | `checksum is VALID` |
| pkg 内 Info.plist | `LSMinimumSystemVersion = 13.0` |

---

## 六、新增到测试清单与验收标准

以下条目**并入**产品验收总清单（此前各版本 macOS 均需覆盖）：

- [ ] 在 **macOS 13.0** 上安装并启动（无"需要更高版本"提示）
- [ ] 在 macOS 14 / 15 / 26 上安装并启动
- [ ] macOS 13 上菜单栏图标正常显示
- [ ] macOS 13 上设置窗口可打开（`showSettingsWindow:` 路径）
- [ ] macOS 13 上浅色/深色外观正常
- [ ] 输入监控授权引导在 macOS 13 上路径正确
- [ ] 开机启动（`SMAppService`）在 macOS 13 上可用且默认关闭
- [ ] 安装包拒绝在 < 13.0 系统上安装（`LSMinimumSystemVersion` 生效）

---

## 七、限制与说明

1. **架构**：当前仅 arm64。macOS 13 时代的 Intel Mac 无法运行，如需支持需增加 x86_64 构建（会显著增大包体积，需用户决策）。
2. **无法在本机验证 macOS 13 实际运行**：本机为 macOS 27.2.1。当前验证的是**编译期兼容性 + 产物元数据**。真机 13.0 运行测试需在 VM 或真实 13.x 设备上进行，属待办。
3. 高版本 SDK（27.2）编译低版本目标（13.0）是标准做法，Apple 支持；已通过 `minos` 元数据确认未引入高版本要求。