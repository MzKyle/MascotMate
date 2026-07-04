# 行为系统

## 行为调度器

`BehaviorBrain.gd` 是一个轻量定时器驱动的陪伴决策器。它不直接移动角色，只发出请求：

- `action_requested("walk")`
- `action_requested("idle")`
- `action_requested("edge")`
- `action_requested("invite")`
- `action_requested("sleep")`
- `mischief_requested("grab")`
- `effect_requested("footprint")`
- `prompt_requested("hungry", "...")`
- `decision_observed(decision, context)`

`Main.gd` 接到请求后，会判断当前是否忙碌，再决定是否执行或只显示气泡。

`decide()` 的返回字典会保留原有 `type`、`name` 和 `retry_after` 字段，并附带可选 `intent` 元数据：

- `type` / `name`：意图类型和名称，例如 `care_request:hungry`
- `reason`：触发原因，供测试和调参使用
- `priority`：语义优先级
- `cooldown_key`：冷却归类
- `interruption_level`：打扰等级
- `source`：规则、权重选择或强制触发

这些元数据不会改变现有执行信号接口。行为适配 v1 会额外附带可选 `adaptation` 元数据，用于说明本次决策使用的提示阈值、冷却倍率、权重倍率和适配原因。`decision_observed` 是只读观测信号，也会暴露 `none` 决策的原因，例如忙碌、冷却、暂停或安静模式。自动提示、自动动作和自动特效会同步写入 `companion_events.json`，用于 Companion Model v2 后续记忆聚合。

自动提示气泡会先经过 `CompanionExpressionBank.gd` 解析；如果没有匹配表达，则继续使用 `BehaviorBrain.gd` 信号里的原始 message。表达库只影响气泡文本，不改变决策、动画或状态数值。

`Main.gd` 会把 `CompanionMemory.gd` 的记忆快照和当前皮肤的 `personality` 放入行为上下文。表达库会用这些上下文选择文案；`BehaviorBrain.gd` 也会用它们调整主动提示阈值、自动行为权重和非工作时段冷却。适配不会改变手动互动行为、核心状态数值、信号接口或忙碌/暂停/休息边界。

基础动作权重和陪伴冷却来自：

```text
godot_pet/assets/behavior.json
```

`companion.adaptation` 是可选配置；缺失时默认启用明显适配：

```json
{
  "enabled": true,
  "strength": "visible",
  "active_cooldown_multiplier_range": [0.55, 1.65],
  "mischief_cooldown_multiplier_range": [0.50, 1.80],
  "weight_multiplier_range": [0.25, 2.75]
}
```

配置异常时会回退到代码内置默认值，避免桌宠启动失败。

浏览器陪伴控制台可以覆盖 `enabled` 和 `strength`，覆盖值保存到 `config.json` 的 `app.behavior_adaptation`。控制台不会直接改底层权重数组。

## 本地陪伴控制台

右键菜单的“陪伴控制台”会打开本地浏览器页面。控制台读取 `companion_debug_snapshot.json`，展示当前状态、最近 decision、intent、adaptation、记忆摘要和最近事件。

控制台的固定场景回放会在 Godot 运行时创建临时行为脑执行 dry-run decision，包括工作低打扰、饥饿照料、低心情陪玩、休息边界、忙碌保护和强制捣乱。回放结果写入 `companion_scenario_result.json`，不会触发真实动画、不会写入事件日志，也不会改变状态数值。

## 陪伴上下文

行为脑每次决策会读取：

- 本地时间段：工作、娱乐、休息
- `StateStore.gd` 的心情、饥饿、体力、亲密度
- 最近互动、投喂、提示和自动行为时间
- 当前是否忙碌：抱起、飞行、轻互动、偷看、捣乱演出
- v2 记忆快照和皮肤人格，用于自动事件记录后的记忆刷新、表达上下文和行为适配

饥饿过高会优先低频提示投喂，照料偏好和熟悉度可把提示阈值从 80 降到最低 74；低心情陪玩提示可在高玩心、陪玩偏好和高熟悉度下从 35 提高到最高 50。体力过低或休息时段会倾向睡觉；刚互动过会延长主动打扰冷却。状态被动衰减由行为脑 tick 时触发，最多补算离线 8 小时。

## 安静模式

安静模式仍然运行计时器，但普通 tick 不发出散步或捣乱行为。只有饥饿、体力等必要状态会经过长冷却后给出低频提示。

适合：

- 工作时保持桌面干净
- 录屏或演示
- 只想手动互动

## 活泼模式

活泼模式会在打扰冷却允许时按状态修正权重后决定行为：

| 权重 | 行为 |
| --- | --- |
| 34 | 散步 |
| 18 | 回到闲置 |
| 14 | 贴边走 |
| 14 | 邀请玩 |
| 20 | 脚印小特效 |

这些行为只在不忙碌时执行。工作时段会降低散步、贴边和轻特效权重；低体力会降低走动权重；低心情会提高陪玩邀请权重。行为适配会根据 `playfulness`、`patience`、`clinginess`、熟悉度和陪玩偏好明显改变散步、邀请玩、闲置和脚印的倾向，但工作时段不会缩短基础工作冷却。

## 捣乱模式

捣乱模式的核心是“费力抢鼠标”视觉演出：

- 切换到捣乱模式后约 1 秒试探一次，首轮会绕过普通互动冷却
- 后续触发受捣乱模式冷却、工作时段倍率、休息时段限制和行为适配影响
- 演出持续 4 秒
- 角色窗口贴近鼠标并抖动
- 画出拉扯线和汗滴
- 右上角显示“停”按钮

它不会移动系统鼠标，也不会锁定鼠标。鼠标穿透多边形会被收缩到“停”按钮区域，避免演出期间影响用户操作桌面。

## 忙碌判断

`Main.gd` 的忙碌状态包括：

- 正在抱起或飞行
- 正在轻互动
- 正在偷看
- 正在捣乱演出

行为调度请求必须通过忙碌判断，避免多个状态互相覆盖；切换捣乱后的首轮抢鼠标也不会打断忙碌状态。
