# FCP 时间线缩放/平移控制方式 —— 资料研究（待真实测试校准）

> 日期：2026-11-22 23:06
> 状态：**desk research 完成；结论冲突，必须真实测试后校准。不得据此宣称功能已实现。**

## 一、用户定义的默认操作规则（不可修改，作为测试目标）

| 操作 | 期望效果 |
|---|---|
| Command + 滚轮向上 | 时间线放大 |
| Command + 滚轮向下 | 时间线缩小 |
| Option + 滚轮 | 时间线水平平移 |
| Shift + 滚轮 | 保留 FCP 原生行为 |
| 普通滚轮 | 保留 FCP 原生行为 |

## 二、公开资料证据（来源标注）

1. **Apple 官方文档**（[Final Cut Pro 时间线缩放与滚动](https://support.apple.com/en-cn/guide/final-cut-pro/ver4e2edcc/10.6.6/mac/12.6)）
   - 放大：`显示 > 放大` 或 **Command + 加号 (+)**；缩小：`显示 > 缩小` 或 **Command + 减号 (–)**
   - 缩放工具：**Z 键**；手型平移工具：**H 键**；或拖滚动条
   - **官方文档未提及用鼠标滚轮直接缩放/平移时间线**

2. **CommandPost 开发者指南**（[plugins.finalcutpro.timeline.mousezoom](https://github.com/CommandPost/CommandPost-DeveloperGuide/blob/master/api/plugins/plugins.finalcutpro.timeline.mousezoom.md)）
   - **按住 Option 键 + 机械滚轮 / Magic Mouse 触摸板 → 缩放 FCP 时间线**
   - 与用户规则「Option+滚轮=水平平移」**直接冲突**

3. **社区资料**（[creativecow 论坛](https://creativecow.net/forums/thread/fastest-way-of-navigating-fcp-timeline/page/2)）
   - 「Shift+滚轮水平滚动」是 **macOS 系统级滚动行为**（系统设置→鼠标→滚动方向），并非 FCP 特有

## 三、冲突小结（必须实测的原因）

| 用户规则 | 公开资料 | 冲突 |
|---|---|---|
| Command+滚轮=缩放 | 官方文档只有 Command+加号/减号缩放，无滚轮 | 无法证实是否存在 |
| Option+滚轮=水平平移 | CommandPost：Option+滚轮=**缩放** | **直接冲突** |
| Shift+滚轮=保留 FCP 原生 | 系统级=水平滚动 | 需确认 FCP 内实际效果 |

## 四、本机环境（只读确认）

- Final Cut Pro **12.4**（Build 454072）已安装于 `/Applications/Final Cut Pro.app`（7.5 GB）
- 本轮**未启动/未操作 FCP**

## 五、真实测试计划（授权 + 用户同意后进行）

前置：输入监控权限已授权；FCP 打开一个**测试用空项目/演示库**（只做视图缩放/平移，不编辑素材）。

| 测试 | 步骤 | 判定 |
|---|---|---|
| T1 普通滚轮 | GlideCut 监听关闭，在 FCP 时间线上普通滚动 | 记录 FCP 原生滚动行为（预期垂直滚动） |
| T2 Shift+滚轮 | 同上，按住 Shift 滚动 | 记录 FCP 原生行为（预期水平滚动，若为系统级则同样生效） |
| T3 GlideCut 运行但未映射 | 监听开启（listen-only 不拦截），重复 T1/T2 | 判定监听是否影响 FCP 原生滚动（期望无影响） |
| T4 Command+滚轮 | 由 GlideCut 合成/映射后滚动 | 观测 FCP 时间线是否缩放（放大/缩小方向、作用对象是否为时间线而非浏览器式缩放） |
| T5 Option+滚轮 | 同上，按用户规则应水平平移 | 观测实际效果，与 CommandPost 资料对比，校准映射 |
| T6 退出恢复 | 退出 GlideCut 后重复 T1/T2 | 判定 FCP 滚动恢复原生（期望与 T1/T2 一致） |

> 判定原则：只观察 FCP 时间线视图变化；若任一操作触及素材编辑/时间线内容变更，立即停止并报告。不得以合成事件回调成功代替真机观察。