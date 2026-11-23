# Shift+滚轮功能映射（第二版）—— 实现说明与验证指南

> 2026-11-23 ｜ 针对「保留默认 Shift+滚轮平移，设置中可切换 Option/Control」需求
> 状态：**代码已实现，编译与单元测试通过；真机验证待用户执行**

---

## 一、这次做了什么（与失败过的旧方案的本质区别）

### 旧方案（9 种，全部失败）
新建一个 `CGEvent`（`CGEvent(scrollWheelEvent2Source:)`）再 `post()` 注入。
**FCP 会识别并过滤所有合成事件** —— AX 读取时间线滚动条 value 注入前后完全不变（0.000%）。

### 新方案：功能映射（真实事件原地改写）
在事件 tap 回调里拿到**系统产生的真实滚动事件**，只把它的 flags 从 Option/Control
**原地改写为 Shift**，然后把**同一个事件对象**返回给系统继续传递。

| 维度 | 旧方案 | 新方案（本次） |
|---|---|---|
| 事件来源 | 合成（`combinedSessionState`） | 真实（`hidSystemState`，未改动） |
| 滚动相位/惯性 | 需手工伪造 | 原样保留 |
| 时间戳/增量/坐标 | 需手工构造 | 原样保留 |
| FCP 视角 | 合成事件 → 过滤 | 真实 Shift+滚轮 → 走原生平移 |

实现要点：
- `EventTapController` 事件去向从二态（放行/吞掉）扩展为三态，新增 `.remappedToShift`。
- `WheelTransformer` 新增 `remapPanToShift()`，只改 `event.flags`，绝不碰其他字段。
- `ModifierState.shiftedFlags(from:replacing:)` 是可单测的纯函数。
- 默认平移键从 Option 改为 **Shift**；设置中可选 Shift / Option / Control。
- 存量配置自动迁移（旧版默认 Option → Shift）。
- Command+滚轮缩放、其他应用隔离、普通滚轮放行逻辑均**未改动**。

---

## 二、已完成验证（离线，全部通过）

```
Debug 编译：    BUILD SUCCEEDED
Release 编译：  BUILD SUCCEEDED
单元测试：      23 tests, 0 failures
```

其中新增 4 项针对功能映射的测试，关键一项验证了核心前提：
**原地改写 flags 后，事件来源（eventSourceStateID）和滚动增量（deltaAxis1）均未改变** ——
即改写后的事件仍是真实事件，不是合成事件。

> 注意：这只能证明「改写动作本身正确」，**不能**证明「FCP 接受改写后的事件」。
> 后者必须真机验证，历史上正是在这里出现假阳性。

---

## 三、真机验证（请按此执行）

### 为何必须这样验证
历史记录中曾有 3 次「突破」误报，全部是 **FCP 窗口反复变成 1px 又恢复** 造成的
截图像素差分假阳性。**本项目只采信 AX 数值**，绝不用截图判定。

为此提供只读验证工具 `Verification/PanVerifier`（已用 `GlideCut Local Signing` 签名，
辅助功能权限已就绪）。它**不注入任何事件**，只读取 FCP 时间线的滚动条数值。

### 准备
1. 编译产物（已就绪）：
   `~/Library/Developer/Xcode/DerivedData/GlideCut-*/Build/Products/Release/GlideCut.app`
2. 启动 FCP，打开一个**测试用项目**，让时间线可见（只做视图操作，不改素材）。
3. 确认 GlideCut 已获得「输入监控」+「辅助功能」权限（设置窗口里可查看）。

### 判据：基准先行（两步缺一不可）

**步骤 A —— 建立基准**
1. 关闭 GlideCut 的滚轮增强开关（菜单栏或设置窗口）。
2. 终端运行：`cd /Users/cc-mac/Developer/GlideCut && ./Verification/PanVerifier 60`
3. 在 FCP 时间线上**真实滚动 Shift+滚轮**（这是 FCP 原生水平平移，必定有效）。
4. 记下工具打印的、确实发生变化的读数编号（如 `#3 ... 0.0 → 12.5`）。
   - 若**没有任何读数变化**：说明 FCP 时间线滚动条 value 不随平移改变，
     此指标不可用 → 请停止，换用「播放头位置」判据（见第五节），不要强行判定。

**步骤 B —— 测试映射**
1. 开启 GlideCut 滚轮增强开关，设置窗口把「水平移动时间线」选为 **Option**。
2. 再次运行 `./Verification/PanVerifier 60`。
3. 在 FCP 时间线上**真实滚动 Option+滚轮**。
4. 观察步骤 A 中那个读数编号：
   - **同样变化** → 功能映射成功，Option+滚轮已驱动原生水平平移。
   - **完全不变** → 映射未生效（FCP 仍过滤了改写后的事件），如实记录。

### 对照实验（强烈建议）
步骤 B 后，把设置切回 **Shift**，真实滚动 Shift+滚轮。读数应仍与步骤 A 一致——
这证明改动没有破坏 FCP 原生平移。

---

## 四、结果记录模板

```
步骤 A 基准（原生 Shift+滚轮，GlideCut 关）：
  变化读数编号 = ___    示例值：___ → ___

步骤 B 测试（Option+滚轮，GlideCut 开，平移键=Option）：
  同一读数是否变化 = 是 / 否    示例值：___ → ___

对照（Shift，GlideCut 开）：
  同一读数是否变化 = 是 / 否

结论：功能映射 □成功  □未生效
```

---

## 五、备选判据：播放头位置（若滚动条 value 不响应）

若步骤 A 发现滚动条 value 恒定不变，改用时间线**播放头（playhead）的水平位置**：
1. 在 FCP 时间线上随意点击定位播放头，记下它相对时间线的水平位置。
2. 按步骤 A/B 滚动，观察**时间线内容相对播放头是否水平移动**
   （即相同的素材片段是否移到了不同位置）。
3. 这是视图状态变化，仍需多次重复确认稳定，避免把窗口动画误判为平移。

---

## 六、回滚

改动前已备份全部原文件到 `.backup_shift_mapping_20261123/`（项目未使用 git）。
如需回滚，用该目录中的文件覆盖对应路径即可。
