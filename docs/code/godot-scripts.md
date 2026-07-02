# Godot 脚本导读

## `Main.gd`

核心职责：

- 读取环境变量并配置窗口
- 创建并连接所有运行时模块
- 每帧更新动画、物理和窗口位置
- 处理右键菜单命令
- 控制偷看、捣乱、小游戏和状态气泡
- 更新鼠标穿透多边形

`_input()` 的处理顺序很重要。截图贴图、捣乱停按钮、小游戏和普通交互都有自己的输入优先级。

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

## GDScript 修改建议

- 新行为尽量先在独立脚本里实现，再由 `Main.gd` 编排。
- 涉及窗口位置时，先确认使用的是全局屏幕坐标还是窗口局部坐标。
- 涉及透明窗口时，同时检查鼠标穿透区域。
- 涉及资源加载时，优先使用 `repo_root` 拼接外部资源路径。
- 涉及状态持久化时，写入 `~/.config/mascotmate-desktop`。
