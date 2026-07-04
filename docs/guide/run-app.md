# 从源码运行

本文面向开发者，说明如何在本地启动 Godot 桌宠、验证主要入口，并排查窗口环境问题。普通用户优先看根目录 README。

## 第一次启动

在仓库根目录执行：

```bash
python3 scripts/setup_dev_environment.py
scripts/setup_godot.sh
python3 scripts/generate_godot_manifest.py
scripts/run_godot_pet.sh
```

关键步骤：

- `setup_dev_environment.py` 准备 Python 依赖和 helper 构建环境。
- `setup_godot.sh` 查找或下载 Godot runtime。
- `generate_godot_manifest.py` 扫描 `resource_hd/`，生成 `godot_pet/assets/actions.json` 和内置默认皮肤清单。
- `run_godot_pet.sh` 设置 `CRAYON_PET_ROOT`、透明窗口和鼠标穿透相关环境变量，然后启动 Godot 项目。

## 安全窗口模式

透明窗口、置顶和鼠标穿透依赖桌面环境。若启动后看不到窗口、无法点击、点击穿透异常，先用普通窗口排查：

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

安全窗口模式会关闭透明背景组合，适合确认 Godot、资源路径和脚本逻辑是否正常。

## 开发版常用环境变量

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `GODOT_BIN` | 空 | 指定 Godot 可执行文件 |
| `GODOT_VERSION` | `4.6.3-stable` | setup 脚本下载 Godot 的版本 |
| `CRAYON_PET_ROOT` | 运行脚本自动设置 | 资源根目录 |
| `CRAYON_PET_SAFE_WINDOW` | `0` | 开启后禁用透明窗口组合 |
| `CRAYON_PET_TRANSPARENT` | `1` | 是否启用透明窗口 |
| `CRAYON_PET_ALWAYS_ON_TOP` | `1` | 是否置顶 |
| `CRAYON_PET_BORDERLESS` | `1` | 是否无边框 |
| `CRAYON_PET_MOUSE_PASSTHROUGH` | `1` | 是否启用鼠标穿透多边形 |
| `CRAYON_PET_ENABLE_GLOBAL_HOTKEYS` | `1` | 是否启动全局快捷键 helper |

## 运行后入口

| 操作 | 运行时路径 |
| --- | --- |
| 点击头部/身体 | `InteractionController.gd` -> `Main.gd._on_single_clicked()` |
| 长按抱起/释放 | `InteractionController.gd` -> `PetPhysics.gd` |
| 贴边偷看 | `Main.gd` + `PeekController.gd` |
| 双击逗一逗 | `MiniGames.gd` |
| 滚轮状态 | `StateStore.gd` 快照 |
| 右键菜单 | `PetMenuController.gd` -> `Main.gd._on_menu_command()` |
| 自动行为 | `BehaviorBrain.gd` + `CompanionBehaviorPolicy.gd` |
| 气泡表达 | `CompanionExpressionResolver.gd` + `CompanionExpressionBank.gd` |
| 截图贴图 | `ScreenshotPins.gd` + `pet_helper.py` |

## 右键菜单当前功能

- 散步、饭团投喂、睡觉、唤醒、逗一逗。
- 显示大小 `100% / 125% / 150%`。
- 重力开启/关闭。
- 偷看状态下显示“出来”。
- 皮肤商店、陪伴控制台、截图贴图设置。
- 行为模式：安静、活泼、捣乱。
- 文案语气：温柔、元气、安静。
- 清理捣乱物、退出。

显示大小、重力、当前皮肤、文案语气和截图贴图设置会写入 `config.json`；行为模式每次启动默认回到安静。

## 截图贴图快捷键

| 快捷键 | 效果 |
| --- | --- |
| `F1` | 区域截图，保存历史并复制到剪贴板 |
| `F3` | 轮换贴出最近截图，最多 3 张 |
| `F4` | 关闭当前贴图 |

如果全局快捷键在 Wayland 或权限受限环境下不可用，窗口聚焦时仍可由 Godot 处理应用内快捷键。

## 开发校验

运行时 smoke：

```bash
python3 scripts/run_godot_smoke.py
```

完整常用检查：

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
python3 scripts/validate_skin_catalog.py --check
python3 scripts/run_godot_smoke.py
python3 -m unittest discover tests
```
