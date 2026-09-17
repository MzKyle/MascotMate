# 窗口与物理

## 窗口配置

`PetWindowController.gd` 读取环境变量，并拥有 Godot `Window` / `Viewport` 的平台窗口配置：

| 配置 | 作用 |
| --- | --- |
| `borderless` | 去掉系统窗口边框 |
| `always_on_top` | 保持桌宠在桌面上方 |
| `transparent` | 允许透明背景 |
| `unresizable` | 禁止用户改变窗口大小 |
| `get_viewport().transparent_bg` | 让渲染背景透明 |

当 `CRAYON_PET_SAFE_WINDOW=1` 时，会关闭透明窗口组合，用普通窗口启动，便于排查问题。

## 窗口坐标即物理坐标

桌宠不是在一个全屏 canvas 里移动，而是移动 Godot 窗口本身。`PetPhysics.gd` 保存的 `position` 对应窗口左上角坐标。`Main.gd` 只在需要物理推进的状态决定目标位置，实际窗口写入交给 `PetWindowController.gd`：

```gdscript
if _physics_needs_tick():
	physics.tick(delta, window_controller.play_area(), Vector2(window_controller.size()), _movement_contact_rect())
	window_controller.apply_position(physics.position)
```

`_physics_needs_tick()` 当前覆盖 `Grabbed`、`Flinging`、`Falling`、`Walk`、`WallAttached`、`EdgeWalk`。`Idle`、`Landing`、`Peeking` 等不需要持续推进的位置状态会跳过物理和窗口位置写入，降低空闲占用。

这样的好处是桌宠可以像独立桌面对象一样漂浮、落地和贴边，不需要占用整屏透明窗口。

窗口位置和尺寸由 `PetWindowController.gd` 先比较再写入。需要保持窗口中心时，`Main.gd` 会在调用 controller 后同步更新 `physics.position`，避免下一次进入运动状态时从旧坐标跳动。

## 接触矩形

PNG 动画帧可能存在透明留白。`PetSprite.gd` 会用 `Image.get_used_rect()` 记录当前帧实际可见区域，并在 `visible_rect_for_rotation()` 中计算旋转后的包围矩形。

`Main.gd` 再把这个可见矩形传给物理模块，用于屏幕边界碰撞：

```text
可见矩形 -> 接触矩形 -> 水平/垂直限制 -> 窗口坐标修正
```

这能减少“看起来没碰到边缘却反弹”的错觉。

## 重力与碰撞

`PetPhysics.gd` 的主要参数：

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `GRAVITY` | `2200.0` | 垂直加速度 |
| `DAMPING` | `0.985` | 速度阻尼 |
| `FLOOR_BOUNCE` | `0.35` | 地面反弹系数 |
| `WALL_BOUNCE` | `0.45` | 墙面反弹系数 |
| `LANDING_SPEED` | `90.0` | 落地速度阈值 |

快速撞到左右墙且速度较慢时，桌宠会进入 `WallAttached`，再可进入贴边行走。

## 鼠标穿透

透明窗口不应该整块拦截鼠标。`Main.gd` 仍负责根据宠物、小游戏、偷看、捣乱和气泡状态计算可点击区域，但实际提交由 `PetWindowController.gd` 通过 `Window.mouse_passthrough_polygon` 完成：

- 普通状态和逗一逗：只让角色可见区域附近接收事件
- 投喂状态：整个窗口接收事件，方便拖拽饭团
- 偷看状态：整个小窗口接收事件，方便点击唤回
- 捣乱演出：整个演出窗口接收事件，右上角“停”按钮可停止

`PetWindowController.gd` 会缓存上一次写入的穿透多边形。多边形没有变化时不会重复设置 `Window.mouse_passthrough_polygon`，减少透明窗口环境下的无效窗口系统调用。

如果桌面环境对穿透支持不好，可以关闭：

```bash
CRAYON_PET_MOUSE_PASSTHROUGH=0 scripts/run_godot_pet.sh
```
