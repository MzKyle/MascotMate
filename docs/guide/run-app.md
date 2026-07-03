# 开发运行

## 第一次启动

在仓库根目录执行：

```bash
scripts/setup_godot.sh
python3 scripts/generate_godot_manifest.py
scripts/run_godot_pet.sh
```

`generate_godot_manifest.py` 会扫描 `resource_hd/` 中的动作帧，并生成：

```text
godot_pet/assets/actions.json
```

Godot 运行时会读取这个动作清单，再由 `PetSprite.gd` 按动作加载图片帧。

## 安全窗口模式

如果当前桌面环境不支持透明窗口，或透明窗口导致鼠标事件异常，可以先用安全窗口模式排查：

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

安全窗口模式会关闭透明背景相关行为，使用普通窗口显示桌宠。它适合确认 Godot、资源路径和脚本逻辑是否正常。

## 常用环境变量

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `GODOT_BIN` | 空 | 指定 Godot 可执行文件 |
| `GODOT_VERSION` | `4.6.3-stable` | setup 脚本下载 Godot 的版本 |
| `CRAYON_PET_ROOT` | 自动设置 | 资源根目录，运行脚本会指向仓库根目录 |
| `CRAYON_PET_SAFE_WINDOW` | `0` | 开启后禁用透明窗口组合 |
| `CRAYON_PET_TRANSPARENT` | `1` | 是否启用透明窗口 |
| `CRAYON_PET_ALWAYS_ON_TOP` | `1` | 是否置顶 |
| `CRAYON_PET_BORDERLESS` | `1` | 是否无边框 |
| `CRAYON_PET_MOUSE_PASSTHROUGH` | `1` | 是否启用鼠标穿透多边形 |
| `CRAYON_PET_ENABLE_GLOBAL_HOTKEYS` | `1` | 是否启用跨平台全局快捷键辅助进程 |

## 运行后的入口

桌宠启动后默认进入安静模式。主要操作：

| 操作 | 效果 |
| --- | --- |
| 单击头部 | 摸摸头，增加心情和亲密度 |
| 单击身体 | 戳一戳 |
| 长按 350ms | 抱起角色 |
| 快速释放 | 按释放速度甩飞 |
| 拖到屏幕边缘释放 | 进入贴边偷看 |
| 双击 | 开始逗一逗 |
| 滚轮 | 显示心情、饥饿、体力、亲密度 |
| 右键 | 打开动作、模式、显示大小、重力、截图贴图设置和退出菜单 |

截图贴图默认快捷键：

| 快捷键 | 效果 |
| --- | --- |
| `F1` | 区域截图，保存历史并复制到剪贴板 |
| `F3` | 轮换贴出最近截图，最多 3 张 |
| `F4` | 关闭当前贴图 |

## 常用命令

```bash
python3 scripts/generate_godot_manifest.py
scripts/run_godot_pet.sh
scripts/build_godot_linux.sh
scripts/install_desktop_entry.sh
```
