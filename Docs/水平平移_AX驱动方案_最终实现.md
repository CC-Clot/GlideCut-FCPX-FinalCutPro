# 水平平移：AX 驱动方案（最终实现）

日期：2026-11-23
状态：**已编译、28 项测试通过、端到端真机验证通过；方向校正后待用户重装验证**

## 一、为什么放弃事件改写（前 4 版）

| 版本 | 做法 | 真机结果 |
|---|---|---|
| 1 | 改 flags 高位为 Shift | 时灵时不灵 |
| 2 | 高低位设备位同步改 `0x80020→0x20002` | 仍时灵时不灵 |
| 3 | 参考 Mos 搬轴 Δ1→Δ2 | 完全不平移（方向错误） |
| 4 | 撤销搬轴 + 换 tap 层到 annotatedSession | 仍不平移 |

**根因**：FCP 是 AppKit 应用，构造 `NSEvent.modifierFlags` 时会用**物理按键的真实状态**覆盖事件里伪造的 Shift。你实际按的是 Option，所以伪造的 Shift 时而被认、时而被覆盖。软件无法改变物理按键状态，这条路天生不可靠。

## 二、AX 方案为什么可靠——真机探测的确凿证据

用只读 AX 探针（`Verification/AXProbe.swift`）扫描当前 FCP **12.4**，发现历史文档（旧版）的结论已过时：

1. **时间线 `AXScrollArea` 支持标准滚动 action**：`AXScrollLeftByPage` / `AXScrollRightByPage`。
2. **水平滚动条支持直接设值**（`Verification/TimelineScrollProbe.swift` 实测）：
   - `AXScrollRightByPage` → 滚动条 value `0.000000 → 1.000000`（真的平移）
   - `AXScrollLeftByPage` → `1.000000 → 0.000000`（可逆）
   - `AXUIElementSetAttributeValue` 设值 0→0.5→1 → `AXError=0`，value 精确生效
   - **全程播放头时间码 `00:00:21:22` 不变** → 证明是「平移视图」而非「移动播放头」
3. 缩放从第一版起始终稳定，正是因为它走 AX 菜单点击。平移现在走**同一条系统辅助功能路径**。

> 历史文档「AX 滚动条设值不生效、无 action、时间线 0 个可操作元素」是旧版 FCP 的结论，**FCP 12.4 已完全不适用**。

## 三、实现

- `WheelTransformer.axPanTimeline`：Option/Control+滚轮的增量在 8ms 窗口内合并，方向映射为滚动条 value 偏移。
- **方向校正**：用户真机反馈方向相反，已将映射整体取反——物理上滚（`.down`，本机 Δ1 > 0）→ value 减小；物理下滚（`.up`）→ value 增大。纯函数 `ModifierState.panSign(for:)` 已加入回归测试，默认 Shift 与缩放方向均不受影响。
- `ModifierState.panStep`（纯函数）：幅度→步长，钳制 0.01~0.08，避免一格冲到底或几乎不动。
- `FCPMenuDriver.panTimeline`：读取时间线滚动条当前 value，加增量后设回，结果写日志。滚动条元素带缓存（5s TTL）。
- 主线程执行 AX 调用（沿用缩放的实测结论）。
- 默认 Shift+滚轮仍走 FCP 原生平移，不干预，手感不变。
- 事件 tap 保持 `.cgAnnotatedSessionEventTap` + `.tailAppendEventTap`。

## 四、验证状态

| 项 | 结果 |
|---|---|
| 28 项单元测试 | 全过（含平移方向、方向回归、步长边界） |
| Debug / Release 编译 | 均 SUCCEEDED，0 错误 |
| AX 能力真机探测 | 设值 AXError=0，value 精确变化，播放头不变 |
| **端到端**（调用产品代码 `panTimeline`） | `0.10→0.40→0.10`，可逆、精确 |
| 重装后滚轮体验 | **待用户验证** |

## 五、验证方法

1. 重装（新产物 SHA `ffb24c89…`）：运行 `更新安装_功能映射版.command`。
2. 打开 FCP 测试项目，显示时间线，设置中把平移键设为 Option 或 Control。
3. 在时间线上**连续滚动** Option+滚轮 / Control+滚轮，观察时间线是否水平平移。
4. 日志路径 `~/Library/Application Support/GlideCut/glidecut.log`，正常应见：
   ```
   平移执行: Δ=+0.0400 结果=滚动条 0.1200→0.1600
   ```
5. 手感（步长 0.01~0.08）如觉得太快或太慢，告诉我，调 `ModifierState.panStep` 的系数即可。

## 六、客观验证工具（可选）

- `Verification/AXProbe.swift`：只读枚举 FCP 菜单与 AX 元素。
- `Verification/TimelineScrollProbe.swift`：`read`/`right`/`left`/`setval <值>` 模式，打印滚动条 value 与播放头时间码，可用于客观复验。
