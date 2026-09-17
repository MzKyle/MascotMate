# Godot 脚本导读

## `Main.gd`

核心职责：

- 创建 `PetWindowController.gd`，由它读取环境变量并配置 Godot 窗口
- 创建并连接所有运行时模块
- 每帧更新动画，并只在运动状态推进物理和窗口位置
- 处理右键菜单命令
- 控制偷看、捣乱、轻互动和状态气泡
- 把行为 intent 执行为气泡、动作、特效或状态变化
- 把当前文案语气、皮肤人格、记忆和画像合并为表达上下文
- 计算鼠标穿透多边形，并交给 `PetWindowController.gd` 去重后提交

`_input()` 的处理顺序很重要。截图贴图、捣乱停按钮、轻互动和普通交互都有自己的输入优先级。

主循环会用 `_physics_needs_tick()` 跳过空闲状态的物理计算；窗口位置、尺寸和透明窗口的 `mouse_passthrough_polygon` 由 `PetWindowController.gd` 先比较再提交给 Godot `Window`。

## `PetSprite.gd`

核心职责：

- 读取动作清单
- 加载 PNG 帧
- 按 FPS 播放动画
- 根据 display scale 计算窗口建议尺寸
- 根据当前帧透明区域计算可见矩形

如果新增动作，通常不需要改这个文件，只需要补资源并更新 `generate_godot_manifest.py`。

## `PetPhysics.gd`

核心职责：

- 保存窗口位置和速度
- 处理 `Grabbed`、`Flinging`、`Falling`、`Walk`、`WallAttached`、`EdgeWalk` 等状态
- 根据屏幕播放区域和角色接触矩形做碰撞限制
- 发出落地、反弹和贴墙信号

物理模块不直接操作窗口，也不播放动画。

## `InteractionController.gd`

核心职责：

- 把 Godot 鼠标事件转换为语义化交互
- 通过计时器区分单击、双击、长按
- 记录鼠标采样并计算释放速度

这个模块不关心角色状态，状态判断由 `Main.gd` 完成。

## `ScreenshotPins.gd`

核心职责：

- 读取和保存截图贴图配置
- 维护最近截图历史和贴图窗口列表
- 调用 Godot 截图和剪贴板 helper
- 启动和停止跨平台快捷键辅助进程
- 通过 UDP 接收全局快捷键命令

这个模块会创建 `PinImageWindow.gd` 和 `ScreenshotSettingsWindow.gd`，并通过 `notify` 信号让主窗口显示气泡提示。

## 陪伴与表达脚本

| 脚本 | 职责 |
| --- | --- |
| `BehaviorBrain.gd` | 定时调度行为，发出 action/prompt/effect/mischief/intent 信号 |
| `CompanionBehaviorPolicy.gd` | 根据状态、时段、记忆、画像和适配强度做规则决策 |
| `CompanionExpressionResolver.gd` | 把 intent 转成 bubble、capability、effect、mini_game 或 mischief |
| `CompanionExpressionBank.gd` | 本地文案库，按 key、tone、关系等级、偏好和最近文案选择气泡 |
| `CompanionAIExpressionClient.gd` | 可选 AI sidecar 客户端、缓存、校验和 fallback 统计 |
| `CompanionEventStore.gd` | 最近 200 条结构化陪伴事件 |
| `CompanionMemory.gd` | 从事件日志聚合短期偏好和最近表达 |
| `CompanionLongTermProfile.gd` | 长期画像、AI 结构化记忆总结和有效偏好 |

表达系统的边界是：本地文案和可选 AI 只影响气泡内容；行为、动画和状态仍由本地规则控制。

## 皮肤与外部 UI

| 脚本 | 职责 |
| --- | --- |
| `SkinManager.gd` | 加载内置/用户皮肤，归一化皮肤能力和 personality |
| `SkinStoreBridge.gd` | 启动浏览器皮肤商店，轮询皮肤选择命令 |
| `CompanionConsoleBridge.gd` | 启动浏览器陪伴控制台，轮询控制台命令 |

浏览器页面本身在 `skin_store/` 和 `companion_console/`，HTTP 服务由 `scripts/skin_store_server.py` 提供。

陪伴调试快照由 `Main.gd` 写入。启动、配置/状态变化、场景回放、退出时会主动写快照；陪伴控制台 helper 运行期间，定时器每 1 秒刷新一次快照供浏览器轮询读取。

## GDScript 修改建议

- 新行为尽量先在独立脚本里实现，再由 `Main.gd` 编排。
- 涉及窗口位置时，先确认使用的是全局屏幕坐标还是窗口局部坐标。
- 涉及透明窗口时，同时检查鼠标穿透区域。
- 涉及资源加载时，优先使用 `repo_root` 拼接外部资源路径。
- 涉及状态持久化时，写入 `~/.config/mascotmate-desktop`。
