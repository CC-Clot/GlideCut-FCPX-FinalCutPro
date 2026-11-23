# GlideCut｜FCPX / Final Cut Pro 时间线滚轮增强插件

> macOS 菜单栏辅助工具（非 FCPX 内置插件），为 Final Cut Pro / FCPX / FinalCut 提供滚轮增强：时间线平移、缩放与修饰键映射。

一款 macOS 菜单栏常驻工具，为 Final Cut Pro 的时间线操作提供滚轮增强。
仅对 FCP 前台生效，在其他应用中完全放行，不干扰系统滚动。

> 关键词：FCPX插件、Final Cut Pro插件、FinalCut、FCP、时间线平移、滚轮增强、视频剪辑效率工具、macOS 效率插件。

> 当前版本：**V1.0.1**（macOS 13.0+，仅 Apple Silicon arm64）

## 功能

| 输入 | 行为 |
|---|---|
| Command + 滚轮 | 时间线缩放 |
| Shift + 滚轮 | 水平平移（**默认且推荐**，使用 FCP 原生行为，最丝滑） |
| Option / Control + 滚轮 | 水平平移（可在设置中映射，通过辅助功能驱动） |

其它特性：

- 菜单栏常驻，无 Dock 图标
- 权限引导（输入监控 + 辅助功能）
- 开机自启开关
- 中英双语界面
- 关于页含作者联系方式

## 界面

![设置界面](Docs/设置界面_V1.0.1_最终.png)

## 安装

本仓库保留当前版本 PKG 安装包，不保留 DMG：

双击 `发行包/GlideCut-1.0.1.pkg`，按安装向导完成安装（安装前会展示使用声明）。
DMG 仅作为本地构建校验产物，不随仓库发布。

也可运行 `更新安装_V1.0.1.command`（需本地 PKG，安装前需阅读并确认使用声明）。

> 首次运行需授予「输入监控」与「辅助功能」权限。因未做 Developer ID 签名与公证，
> 首次打开如遇 Gatekeeper 提示，请右键 → 打开。

## 源码构建（可选）

```bash
# 1. 构建 Release
xcodebuild -project GlideCut.xcodeproj -scheme GlideCut -configuration Release build

# 2. 运行测试
xcodebuild -project GlideCut.xcodeproj -scheme GlideCutTests -configuration Debug \
  -destination 'platform=macOS' test

# 3. 把构建产物装到“应用程序”
APP=$(find ~/Library/Developer/Xcode/DerivedData/GlideCut-*/Build/Products/Release \
  -maxdepth 1 -name GlideCut.app -type d | head -1)
cp -R "$APP" /Applications/
```

也可用 Xcode 打开 `GlideCut.xcodeproj`，选择 `GlideCut` scheme 直接运行。

## 目录结构

```
GlideCut/
├── GlideCut.xcodeproj/      Xcode 工程
├── GlideCut/                 应用源码
│   ├── App/                  菜单栏、设置界面、窗口
│   ├── Core/                 事件监听、滚轮变换、权限、设置
│   ├── Localization/         中英本地化
│   ├── Resources/            图标与二维码资源
│   └── Info.plist
├── Tests/                    单元测试（28 项）
├── Verification/             验证探针工具
├── Docs/                     技术与验收文档
├── 发行包/                    V1.0.1 PKG 安装包与校验清单（DMG 不随仓库发布）
└── 更新安装_V1.0.1.command   安装脚本（需本地 PKG，见校验清单）
```

## 技术说明

- 事件监听用 `CGEvent Tap`，缩放通过 AX 菜单点击，Option/Control 平移通过 AX 设值时间线滚动条。
- 关于平移方案的技术决策与历史踩坑记录，见 `Docs/水平平移_AX驱动方案_最终实现.md`
  与 `开发清单_GitHub准备版.md`。
- 完整的开发状态与文档索引见 `开发清单_GitHub准备版.md`。

## 许可

仅供个人学习、研究与自用，禁止商业转卖或捆绑收费。详见 [LICENSE](LICENSE)。
如需授权、反馈或合作：keyframecc@foxmail.com
