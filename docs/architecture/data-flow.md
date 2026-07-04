# 数据流

## 启动流程

```mermaid
sequenceDiagram
  participant Shell as run_godot_pet.sh
  participant Setup as setup_godot.sh
  participant Godot as Godot Runtime
  participant Main as Main.gd
  participant Sprite as PetSprite.gd
  participant State as StateStore.gd

  Shell->>Setup: 查找 Godot 可执行文件
  Setup-->>Shell: 返回 GODOT_BIN_PATH
  Shell->>Godot: --path godot_pet
  Godot->>Main: 加载 Main.tscn
  Main->>Main: 解析 CRAYON_PET_* 环境变量
  Main->>Sprite: configure(repo_root, actions.json)
  Main->>State: load_state()
  Main->>Main: 配置透明窗口并同步尺寸
```

## 交互到物理

长按抱起和释放甩飞的链路：

```mermaid
sequenceDiagram
  participant User as 用户
  participant Input as InteractionController
  participant Main as Main.gd
  participant Physics as PetPhysics.gd
  participant Window as Godot Window

  User->>Input: 左键按下 350ms
  Input-->>Main: grab_started(global_pos)
  Main->>Physics: begin_grab(global_pos - drag_offset)
  User->>Input: 移动鼠标
  Input-->>Main: grab_moved(global_pos)
  Main->>Physics: update_grab(target)
  User->>Input: 松开鼠标
  Input-->>Main: grab_released(velocity, held, global_pos)
  Main->>Physics: release(velocity, flinging)
  Main->>Main: _physics_needs_tick()
  Physics-->>Main: 运动状态更新 position
  Main->>Window: 位置变化后写入 window.position
```

空闲或不需要物理推进的状态不会每帧调用 `PetPhysics.tick()`，窗口位置也会先比较再写入。这样保持窗口坐标即物理坐标的模型，同时降低空闲 CPU 和窗口系统调用。

## 资源加载

`PetSprite.gd` 不直接扫描目录。它读取 `actions.json` 中的动作定义，并从统一资源目录加载：

```text
resource_hd/<relative_path>
```

如果暂时只有较低清晰度的素材，也直接放入 `resource_hd/` 对应动作目录，后续替换同名文件即可。

## 截图贴图链路

```mermaid
sequenceDiagram
  participant Hotkey as pet_helper
  participant Pins as ScreenshotPins.gd
  participant Tool as Godot screenshot / clipboard helper
  participant Config as ~/.config
  participant Pin as PinImageWindow.gd

  Hotkey-->>Pins: UDP screenshot / paste_pin / close_pin
  Pins->>Tool: 区域截图到 PNG
  Pins->>Config: 保存截图历史
  Pins->>Pin: 创建置顶透明子窗口
  Pin-->>Pins: activated / close_requested
```

贴图窗口本身由 Godot `Window` 实现。图片会按屏幕尺寸做最大尺寸限制，避免贴图大到超出屏幕。

## 状态数据

角色状态以四个核心数值为主，并附带互动记忆：

| 字段 | 含义 | 范围 |
| --- | --- | --- |
| `mood` | 心情 | 0-100 |
| `hunger` | 饥饿 | 0-100 |
| `energy` | 体力 | 0-100 |
| `affection` | 亲密度 | 0-100 |

`StateStore.gd` 还保存 `last_decay_at` 和 `memory`，用于被动衰减、最近互动、投喂、提示和自动行为冷却。保存采用短 debounce，并在退出时 flush。行为模式不保存，每次启动默认回到安静模式。
