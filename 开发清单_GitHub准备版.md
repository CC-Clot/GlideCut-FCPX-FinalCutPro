# GlideCut 开发清单（GitHub 准备版）

> 整理时间：2026-11-23  
> 项目路径：`/Users/cc-mac/Developer/GlideCut`  
> 当前版本：**V1.0.1**（关于页与安装包一致）  
> 用途：整合最初提供的 MD 文档清单、Shift 功能映射 / AX 平移 / UI 改版全部新增文档，作为上传 GitHub 前的**唯一完整开发清单**。本清单取代旧的 `MD文档清单.md`（保留为历史索引）。

---

## 一、产品定位与当前交付状态

### 1.1 产品定位

GlideCut 是一款 **macOS 菜单栏常驻工具**（LSUIElement），仅对 **Final Cut Pro** 生效：

- **Command + 滚轮** → 时间线缩放（AX 菜单驱动）
- **Shift + 滚轮** → 保留 FCP 原生水平平移，**默认且推荐**
- **Option / Control + 滚轮** → 通过 AX 直接设值时间线水平滚动条实现平移
- 非 FCP 应用：事件全部放行，不干扰系统滚动

### 1.2 V1.0.1 相对 V1.0 的变更

| 项目 | V1.0 | V1.0.1（本次） |
|---|---|---|
| 界面布局 | 左侧导航 + 右侧内容 700×720 | **恢复顶部展示**，单列分区，720×840 单页无滚动 |
| 分区样式 | 左侧导航高亮 | **通用/修饰键/权限/关于 四个分区加圆角边框突出** |
| 水平平移提示 | 旧描述 | **建议使用默认shift原生平移更丝滑。** |
| 关于区 | 版本/日期/链接/免责 | **关于 GlideCut**：当前版本 V1.0 / 系统要求 MacOS 13.0+ / 开发者 CCstudio + 四张居中二维码（微信赞赏、支付宝、联系作者、关注抖音）+ 邮箱一键复制 + 免责文案 |
| 二维码资源 | 无 | 新增 `QRReward`（微信赞赏）/ `QRAlipay`（支付宝）/ `QRWechat`（联系作者）/ `QRDouyin`（关注抖音，白底精修）四个图片资源（Assets.xcassets） |
| 版本号 | 1.0 (build 1) | **1.0.1 (build 2)**，APP 关于页显示 V1.0.1 |

### 1.3 已完成项总表

| 模块 | 状态 | 说明 |
|---|---|---|
| 事件监听 | 已完成 | CGEvent Tap，仅 FCP 前台生效 |
| 修饰键识别 | 已完成 | Command / Option / Control / Shift 及组合 |
| 时间线缩放 | 已完成 | AX 菜单点击，方向已按用户直觉校正 |
| Shift 原生平移 | 已完成 | 默认路径，不改写事件，保留原生手感 |
| Option/Control AX 平移 | 已完成 | 直接设值滚动条，方向已按真机反馈校正 |
| 权限系统 | 已完成 | 输入监控 + 辅助功能，状态轮询与引导 |
| 开机启动 | 已完成 | SMAppService 注册，开关独立 |
| 设置界面 | 已完成 | 顶部展示，720×840 单页无滚动，四分区边框 |
| 关于信息 | 已完成 | 关于 GlideCut / 版本 / 系统要求 / 开发者 / 四张二维码 / 邮箱一键复制 / 免责文案（无开源/常见问题/反馈链接） |
| 中英本地化 | 已完成 | `zh-Hans` / `en` 两套文案 |
| 单元测试 | 已完成 | 28 项全部通过 |
| Release 构建 | 已完成 | 0 错误，macOS 13.0+ |
| PKG / DMG | 已完成 | V1.0.1 本次重新生成并校验 |

---

## 二、关键技术决策（接手开发必读）

| 决策 | 结论 | 原因 |
|---|---|---|
| 是否伪造 Shift 事件 | **否** | FCP 用物理按键状态覆盖事件 flags，4 版事件改写方案均失败 |
| 是否合成 CGEvent / post | **否** | FCP 过滤合成事件，不能可靠驱动时间线 |
| 缩放方案 | AX 菜单点击 | 稳定、低延迟，已验证 |
| 平移方案 | AX 设值时间线滚动条 | FCP 12.4 实测支持，播放头时间码不变 |
| 平移方向 | 物理上滚 → value 减小；下滚 → value 增大 | 真机反馈校正，纯函数 `ModifierState.panSign(for:)` 已回归测试 |
| 默认平移键 | Shift | 原生最丝滑，UI 提示已改为推荐默认 |
| Tap 层级 | `.cgAnnotatedSessionEventTap` + `.tailAppendEventTap` | 当前稳定配置 |
| 事件合并窗口 | 8ms | 减少 AX 调用，兼顾跟手感 |
| 二维码图片 | Pillow 裁剪精修为 680×680 方图 | 去掉营销色块，保留四角定位框，可扫描；抖音码用圆形蒙版去深色背景转白底 |
| 关于页版本显示 | `V1.0.1` | 与安装包一致，见 `SettingsView.AboutMetadata` |

### 历史误报说明

旧文档中多次「Option/Control 平移成功」的结论后来被撤回，原因是 **FCP 窗口尺寸异常变化造成的像素假阳性**。这些文档保留用于记录踩坑过程，不能作为当前技术结论：

- `Docs/第一阶段_状态更正与结论.md`
- `Docs/Shift滚轮方案_验证结论.md`
- `Docs/Shift滚轮方案_最终结论.md`

当前唯一有效技术结论见：

- `Docs/水平平移_AX驱动方案_最终实现.md`
- `Docs/水平平移_终极像素验证结论.md`

---

## 三、文档整合结果

### 3.1 数量与来源

| 来源 | 数量 | 说明 |
|---|---:|---|
| 最初提供的 MD 清单 | 18 份 | 17 份 `Docs/` + 1 份 `发行包/` 校验清单 |
| 功能映射 / AX 平移新增 | 6 份 | 功能映射、AX 方案、tap 层级、搬轴方案、像素结论、根因修复 |
| 本清单 | 1 份 | `开发清单_GitHub准备版.md`（统一清单） |
| 历史索引 | 1 份 | `MD文档清单.md`（保留，标注已被取代） |

### 3.2 验收与交付类（5 份）

| 文件 | 说明 |
|---|---|
| `Docs/完整验收报告_V1.0.md` | 主验收报告，GPT 指令清单 50 项逐条核对 |
| `Docs/阶段一验收报告.md` | 早期阶段一验收 |
| `Docs/交付说明_图标与功能状态.md` | 图标接入过程与功能完成度 |
| `发行包/GlideCut-安装包校验清单.md` | pkg/dmg 哈希、逐文件核对、签名状态 |
| `开发清单_GitHub准备版.md` | 本清单 |

### 3.3 技术验证类（4 份）

| 文件 | 说明 |
|---|---|
| `Docs/第一阶段技术原型_验证报告.md` | 核心原型验证 |
| `Docs/第一阶段_最终验证报告.md` | 第一阶段收尾 |
| `Docs/第二阶段_安装与运行验证报告.md` | 安装/启动/菜单栏/日志验证 |
| `Docs/macOS13兼容性说明.md` | 4 处 14+ API 修复、minos 验证 |

### 3.4 状态更正类（含撤回记录，3 份）

| 文件 | 说明 |
|---|---|
| `Docs/第一阶段_状态更正与结论.md` | 撤回「Option 平移成功」误报 |
| `Docs/Shift滚轮方案_验证结论.md` | Shift 方案首次验证（已被最终结论取代） |
| `Docs/Shift滚轮方案_最终结论.md` | 撤回全部「突破」结论 |

### 3.5 缺陷修复与技术研究类（8 份）

| 文件 | 说明 |
|---|---|
| `Docs/窗口与菜单栏修复说明.md` | 双击无窗口 + 设置无响应 |
| `Docs/权限授权失效问题_根因与解决.md` | CDHash 漂移导致 TCC 授权失效 → 自签名证书 |
| `Docs/权限与开关语义_说明.md` | 两种权限、两个开关的语义 |
| `Docs/开关同步与默认开启_修复说明.md` | 菜单栏与窗口开关反键修复 |
| `Docs/缩放方向修正说明.md` | 自然滚动影响 Δ1 符号 |
| `Docs/开机自启与增强开关_修复说明.md` | SMAppService status=3 根因 |
| `Docs/第二阶段_FCP控制方式研究.md` | FCP 控制方式资料研究 |
| `Docs/Shift滚轮功能映射_验证指南.md` | Shift / Option / Control 映射验证步骤 |

### 3.6 AX 平移与 UI 改版新增类（7 份）

| 文件 | 说明 | 结论有效性 |
|---|---|---|
| `Docs/水平平移时灵时不灵_根因与修复.md` | flags 时灵时不灵根因 | 历史 |
| `Docs/水平平移_搬轴方案_根因与实现.md` | Δ1→Δ2 搬轴方案 | 已废弃 |
| `Docs/水平平移_tap层级修复_根因与实现.md` | tap 层级排查 | 已废弃 |
| `Docs/水平平移_终极像素验证结论.md` | 像素级验证 AX 设值确实移动画面 | 有效证据 |
| `Docs/水平平移_AX驱动方案_最终实现.md` | 当前最终实现 | **当前有效** |
| `Docs/UI改版_示例图.html` / `.png` | 上一轮 UI 示例（已被本轮 V1.0.1 界面取代） | 历史 |
| `Docs/设置界面_V1.0.1_最终.png` | **当前 V1.0.1 界面截图（四码 + 邮箱 + 无底部空白）** | 当前 |
| `Docs/设置界面_V1.0.1.png` | 上一版界面截图（三码） | 历史 |

### 3.7 建议 GitHub 文档分类

```text
docs/
├── product/           # 产品说明、验收、交付
│   ├── 完整验收报告_V1.0.md
│   ├── 交付说明_图标与功能状态.md
│   └── 安装包校验清单.md
├── engineering/       # 当前有效技术方案
│   ├── 水平平移_AX驱动方案_最终实现.md
│   ├── 水平平移_终极像素验证结论.md
│   ├── macOS13兼容性说明.md
│   └── 权限授权失效问题_根因与解决.md
├── history/           # 历史探索与撤回记录
│   ├── 第一阶段_状态更正与结论.md
│   ├── Shift滚轮方案_验证结论.md
│   ├── Shift滚轮方案_最终结论.md
│   ├── 水平平移_搬轴方案_根因与实现.md
│   ├── 水平平移_tap层级修复_根因与实现.md
│   ├── 水平平移时灵时不灵_根因与修复.md
│   └── MD文档清单.md
└── verification/      # 验证指南
    ├── Shift滚轮功能映射_验证指南.md
    └── 缩放方向修正说明.md
```

---

## 四、建议 GitHub 仓库结构

```text
GlideCut/
├── README.md                       # 待创建
├── LICENSE                         # 待确认并创建
├── CHANGELOG.md                    # 待创建，首条为 V1.0.1
├── CONTRIBUTING.md                 # 可选
├── 开发清单_GitHub准备版.md         # 本文件，可直接保留
├── GlideCut.xcodeproj/
├── GlideCut/                       # 应用源码
│   ├── App/                        # SettingsView / WindowController / AppDelegate / MenuBarController
│   ├── Core/                       # EventTapController / WheelTransformer / ModifierState / SettingsStore 等
│   ├── Localization/               # zh-Hans / en
│   ├── Resources/Assets.xcassets/  # AppIcon / MenuBarIcon / QRWechat / QRReward / QRAlipay
│   └── Info.plist                  # 版本 1.0.1 (build 2)
├── Tests/CoreLogicTests.swift
├── Verification/                   # 探针与验证脚本
├── Docs/                           # 按第三节重新分类
├── 发行包/                          # 建议改名为 Release/ 或 artifacts/
└── 更新安装_功能映射版.command       # 建议改名为 scripts/install.command
```

---

## 五、GitHub 上传前待办

### 5.1 必须完成

- [ ] 创建 `README.md`：产品介绍、功能说明、截图（用 `Docs/设置界面_V1.0.1_最终.png`）、安装方法、权限说明、常见问题。
- [ ] 确认并创建 `LICENSE`：关于页写「免费开源」，但仓库尚无许可证文件。
- [ ] 替换关于页占位信息（`SettingsView.swift` → `AboutMetadata`）：
  - `repositoryURL` / `issuesURL` / `faqURL`（当前均为 `https://github.com/your-name/GlideCut...`）
- [ ] 将 `MD文档清单.md` 迁入 `docs/history/`（本清单已标注其为历史索引）。
- [ ] 清理 `.backup_*` 目录，不要上传到 GitHub。
- [ ] 添加 `.gitignore`：`build/`、`.backup_*/`、`.DS_Store`、`xcuserdata/`、DerivedData 等。
- [ ] 确认是否公开四张二维码（微信赞赏、支付宝、联系作者、抖音）与本机路径截图证据；如不公开，从仓库移除 `QR*.imageset`。
- [ ] 确认是否公开作者邮箱 `keyframecc@foxmail.com`（关于区与安装声明中均出现）。

### 5.2 建议完成

- [ ] 改名为英文路径：`发行包/` → `Release/`，`.command` 脚本 → `scripts/`。
- [ ] 添加 `CHANGELOG.md`，首条记录 V1.0.1 UI 改版、四码 + 邮箱一键复制、安装使用声明。
- [ ] 若对外分发：补充 Developer ID 签名 + notarization 公证（当前仅本机签名、pkg 未签名）。
- [ ] 补充 GitHub Actions：至少跑 `GlideCutTests`。
- [ ] 若公开分发：补 Developer ID 签名与公证，当前仅本机证书签名、pkg 未签名。
- [ ] 若需要 Intel Mac：当前仅 arm64，需扩建 universal binary。

---

## 六、V1.0.1 安装包信息

| 文件 | 大小（字节） | SHA-256 |
|---|---:|---|
| `发行包/GlideCut-1.0.1.pkg` | 3,105,988 | `e6f781c38485645671170fa5306f82ed72b05deedd129779877d5a087466b1fa` |
| `发行包/GlideCut-1.0.1.dmg` | 3,411,364 | `1c07c46b8465a49d3be2e09f147805b2524047b35c67ab38a55d542a4de198c7` |
| Release 可执行文件（arm64） | 543,024 | `e860acc9534ba0f93c249820506c8d4c219062f46ccdb59e4b69936ab3e44373` |

校验结果：

- `hdiutil verify GlideCut-1.0.1.dmg` → **VALID**
- pkg 标识符：`com.ccmac.GlideCut`，版本 `1.0.1`，安装位置 `/Applications`
- DMG 内 `CFBundleShortVersionString = 1.0.1`，二进制哈希与 Release 源构建一致
- `codesign --verify --strict` → 通过；pkg → 未签名（公开分发需补 Developer ID）
- 单元测试：28 项通过
- Release 构建：SUCCEEDED

> 上一版本 V1.0 的安装包仍保留在 `发行包/GlideCut-1.0.pkg` / `.dmg`，可按需删除。

---

## 七、下一步执行顺序

1. 确认 GitHub 仓库地址与许可证。
2. 替换 `AboutMetadata` 占位信息，再重新构建一次 Release 与安装包。
3. 按第四节调整目录名与 `.gitignore`。
4. 创建 `README.md` / `CHANGELOG.md` / `LICENSE`。
5. `git init` → 首次提交 → 创建 GitHub 仓库 → push。
6. 在 GitHub Releases 上传 V1.0.1 PKG / DMG，填写更新日志。
7. 若需要公开分发，补 Developer ID 签名与公证后重新打包。

---

*本清单是当前开发状态的快照。上传 GitHub 前，请以「第五节待办」作为最终检查表。*
