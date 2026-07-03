# 交互控制

## 输入入口

Godot 的输入事件先进入 `Main.gd._input()`，处理顺序是：

1. 截图贴图快捷键
2. 捣乱演出中的“停”按钮
3. 轻互动拖拽
4. 桌宠常规交互

这个顺序能避免快捷键和投喂拖拽被普通点击逻辑抢走。

## 点击与长按

`InteractionController.gd` 负责把原始鼠标事件转成语义化信号：

| 信号 | 触发方式 |
| --- | --- |
| `single_clicked(local_pos)` | 左键单击 |
| `double_clicked` | 左键双击 |
| `right_clicked(local_pos)` | 右键单击 |
| `wheel_used` | 鼠标滚轮 |
| `grab_started(global_pos)` | 左键按住超过 `0.35s` |
| `grab_moved(global_pos)` | 抱起后移动 |
| `grab_released(velocity, held, global_pos)` | 抱起或按下后释放 |

单击会有一个很短的延迟，目的是给双击识别留出窗口。

## 甩飞速度

控制器会记录最近若干鼠标位置和时间戳，释放时取足够近的一段样本计算速度。`Main.gd` 根据速度决定：

- 速度大于 `420.0`：进入 `Flinging`
- 速度较低：轻放，进入 `Falling` 或 `Idle`

甩飞后播放 `fall` 动作，并由物理模块处理重力和碰撞。

## 贴边偷看

如果长按后把角色拖到屏幕边缘或角落释放，`Main.gd` 会根据释放点判断：

```text
left / right / top / bottom
top_left / top_right / bottom_left / bottom_right
```

进入偷看后：

- 普通角色 sprite 隐藏
- `peek_sprite` 显示对应方向贴边图
- 窗口大小改为 `112 x 140`
- 行为调度暂停
- 点击或拖拽可退出偷看

## 右键菜单

右键菜单提供：

- 散步、饭团投喂、睡觉、唤醒、逗一逗
- 显示大小 `100% / 125% / 150%`
- 重力开关
- 偷看状态下的“出来”
- 截图贴图设置
- 安静、活泼、捣乱模式
- 清理捣乱物
- 退出

菜单项只保存当前运行期状态。行为模式不会跨启动保存。
