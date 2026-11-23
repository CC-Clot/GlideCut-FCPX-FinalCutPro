# GlideCut V1.0.1 安装包校验清单（供审核）

> 最近更新：2026-11-23 23:25
> 审核对象：`发行包/GlideCut-1.0.1.pkg`（仓库保留）与 `发行包/GlideCut-1.0.1.dmg`（本地校验参考，不随仓库发布）
> 产物来源：Xcode 27.2 工程 `GlideCut.xcodeproj`，`Release` 配置构建
> 本清单在 V1.0.1 关于页版本改为 V1.0.1、新免责文案、PKG 安装向导注入使用声明后重新生成

---

## 一、产物文件与哈希

| 文件 | 大小（字节） | SHA-256 |
|---|---|---|
| `GlideCut-1.0.1.pkg` | 3,105,988 | `e6f781c38485645671170fa5306f82ed72b05deedd129779877d5a087466b1fa` |
| `GlideCut-1.0.1.dmg` | 3,411,364 | `1c07c46b8465a49d3be2e09f147805b2524047b35c67ab38a55d542a4de198c7` |
| 内嵌可执行文件 `GlideCut`（arm64） | 543,024 | `e860acc9534ba0f93c249820506c8d4c219062f46ccdb59e4b69936ab3e44373` |

---

## 二、构建环境

- Xcode：**27.2**（Build 27B52）
- 部署目标：**macOS 13.0**（Ventura 及以上），已验证 `LC_BUILD_VERSION minos = 13.0`
- 架构：**arm64 only**（Apple Silicon 单架构）
- Bundle Identifier：`com.ccmac.GlideCut`
- 版本：**1.0.1**（`CFBundleShortVersionString`），Build **2**（`CFBundleVersion`）
- 关于页显示版本：**V1.0.1**（与安装包一致，见 `SettingsView.AboutMetadata`）
- 开发语言：SwiftUI + AppKit + CoreGraphics + CoreFoundation，**零第三方依赖**

---

## 三、应用包内容（Release 构建）

`GlideCut.app`（解包后）完整文件清单：

| 路径 | 大小（字节） |
|---|---|
| `Contents/Info.plist` | 1,602 |
| `Contents/MacOS/GlideCut`（可执行） | 543,024 |
| `Contents/PkgInfo` | 8 |
| `Contents/Resources/AppIcon.icns` | 132,803 |
| `Contents/Resources/Assets.car` | 2,636,968 |
| `Contents/Resources/en.lproj/Localizable.strings` | 2,957 |
| `Contents/Resources/zh-Hans.lproj/Localizable.strings` | 2,951 |
| `Contents/_CodeSignature/CodeResources` | 3,424 |

- `Assets.car` 内含：AppIcon、MenuBarIcon，以及四张精修二维码 `QRReward`（微信赞赏）/ `QRAlipay`（支付宝）/ `QRWechat`（联系作者）/ `QRDouyin`（关注抖音，白底精修），各 680×680，可扫描
- 本地化：内置**英文（en）与简体中文（zh-Hans）**两套资源
- 应用类型：菜单栏常驻（`LSUIElement = true`），无 Dock 图标
- 包结构无符号链接；无可疑文件

---

## 四、校验结果

### 1. dmg 完整性 ✅
`hdiutil verify GlideCut-1.0.1.dmg` → **`checksum of "GlideCut-1.0.1.dmg" is VALID`**
挂载后内容 = `GlideCut.app` + `Applications`（→ /Applications）快捷方式，共 2 项。

### 2. 版本一致性 ✅
- pkg 元信息版本：`1.0.1`
- DMG 内 `GlideCut.app` 的 `CFBundleShortVersionString`：`1.0.1`
- DMG 内二进制 SHA-256 与 Release 源构建一致：`e860acc9...`

### 3. pkg 元信息 ✅
- 格式：xar 容器（compressed TOC）✅
- 标识符：`com.ccmac.GlideCut`，版本 `1.0.1` ✅
- 安装位置：`/Applications` ✅

### 4. 代码签名状态 ⚠️（如实标注）
- 应用包使用本机证书 **`GlideCut Local Signing`** 签名（`TeamIdentifier=not set`），`codesign --verify --strict` 通过
- pkg **无签名**（`pkgutil --check-signature` → `Status: no signature`）
- **未做 Developer ID 签名，未做 notarization 公证**

**含义**：本机安装使用无碍；分发到其他 Mac 首次打开时，Gatekeeper 可能提示「无法验证开发者」，需右键 → 打开，或 `xattr -dr com.apple.quarantine`。正式公开分发前需补 Developer ID 签名 + 公证。

---

## 五、安装与验证步骤

1. **校验哈希**：
   ```bash
   shasum -a 256 GlideCut-1.0.1.pkg GlideCut-1.0.1.dmg
   ```
   与上表比对。
2. **安装 pkg**：双击或
   ```bash
   sudo installer -pkg GlideCut-1.0.1.pkg -target /
   ```
   → 确认 `/Applications/GlideCut.app` 出现。
3. **验证 dmg**：
   ```bash
   hdiutil verify GlideCut-1.0.1.dmg
   hdiutil attach GlideCut-1.0.1.dmg   # 拖 GlideCut.app 到 Applications
   ```
4. **启动验证**：
   ```bash
   open /Applications/GlideCut.app
   ```
   这是**菜单栏应用**——启动后无窗口、无 Dock 图标，请在**屏幕右上角菜单栏**寻找波形图标，点开选「打开设置…」。
   - **重要**：若此前已运行旧版本，必须先从菜单栏点「退出 GlideCut」再重新打开，否则旧进程会继续显示旧界面。
   - 日志：`~/Library/Application Support/GlideCut/glidecut.log`

---

## 六、功能与已知限制

### 当前功能（已实现并验证）
- Command + 滚轮 → FCP 时间线缩放（AX 菜单驱动）
- Shift + 滚轮 → FCP 原生水平平移（默认推荐）
- Option / Control + 滚轮 → AX 设值滚动条实现水平平移
- 权限引导、开机自启、菜单栏开关、单页设置窗口、关于区四码 + 邮箱一键复制
- 安装向导（`更新安装_V1.0.1.command`）安装前展示完整使用声明，需确认后继续

### 已知限制
1. **未签名 / 未公证**——对外分发前必须补 Developer ID + notarization。
2. **仅 arm64**——不支持 Intel Mac。
3. 四张二维码（微信赞赏 / 支付宝 / 联系作者 / 抖音）均为作者个人码，公开分发前请确认是否对外展示。

---

## 更新记录

### V1.0.1（2026-11-23 23:25 终版）
- APP 关于页版本由 V1.0 改为 **V1.0.1**，与安装包一致。
- 免责提示改为：「GlideCut免费提供给个人使用，禁止任何形式的商业转卖或捆绑收费；如需授权、反馈建议或洽谈合作，请联系作者。」
- **PKG 安装向导注入使用声明**：用 productbuild + distribution 重新打包，Welcome / ReadMe / License 面板均含完整声明，双击 PKG 安装即可见。
- 回归测试 28 项全过；Release SUCCEEDED；DMG verify VALID。

### V1.0.1（2026-11-23 23:10）
- 关于区二维码由三张改为**四张**：微信赞赏 / 支付宝 / 联系作者 / 关注抖音（抖音码精修为白底），整体居中排列。
- 移除开源地址 / 常见问题 / 问题反馈三个链接；新增作者邮箱 `keyframecc@foxmail.com` 一键复制。
- 下方提示改为新的免费使用 / 禁止商业转卖免责文案。
- 窗口高度由 840 压缩到 762，消除关于卡片下方底部空白。
- 安装向导增加完整使用声明（使用范围 / 禁止行为 / 免责条款 / 知识产权 / 联系方式），需确认后安装。
- 回归测试 28 项全过；Release SUCCEEDED；DMG verify VALID。

### V1.0.1（2026-11-23 22:10）
- 版本：**1.0.1**（`CFBundleShortVersionString=1.0.1`，`CFBundleVersion=2`）。
- 界面恢复**最初的顶部展示**（App 图标 + 标题 + 副标题 + 运行中徽标），单页无滚动。
- 通用 / 修饰键 / 权限 / 关于四个分区统一加**圆角边框突出**。
- 水平平移提示：「建议使用默认shift原生平移更丝滑。」
- 关于区改为「关于 GlideCut」：当前版本 V1.0 / 系统要求 MacOS 13.0+ / 开发者 CCstudio。
- 回归测试：**28 项全部通过**；Release 构建 SUCCEEDED；DMG `hdiutil verify` VALID。

### V1.0（2026-11-23 早期）
- 700×720 左侧导航单页 UI；方向校正；关于页基础信息。
- 旧包仍在 `发行包/GlideCut-1.0.pkg` / `.dmg`，可按需删除。

---

*校验人：GlideCut 开发侧。以上哈希与大小均为本机实测值，可复算验证。*
