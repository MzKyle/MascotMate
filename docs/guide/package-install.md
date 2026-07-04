# 安装与打包

本文说明当前仓库支持的本地打包方式。默认推荐 Linux portable runtime bundle；Godot export 和跨平台 zip 是补充发布路径。

## Linux portable bundle

默认打包方式不依赖 Godot export templates。脚本会把 Godot runtime、Godot 项目、资源目录、皮肤商店、陪伴控制台和 helper 放到 `dist/MascotMateDesktop/`。

```bash
scripts/build_godot_linux.sh
```

产物入口：

```text
dist/MascotMateDesktop/MascotMateDesktop
```

运行：

```bash
dist/MascotMateDesktop/MascotMateDesktop
```

portable bundle 的优点是稳定、简单、无需安装 export templates；缺点是产物体积更大。

## 用户级 desktop entry

打包完成后安装 Linux 用户级启动器：

```bash
scripts/install_desktop_entry.sh
```

安装位置：

```text
~/.local/share/applications/mascotmate-desktop.desktop
~/.local/share/icons/hicolor/256x256/apps/mascotmate-desktop.png
```

脚本会复制：

```text
packaging/icons/mascotmate-desktop.png
```

这个图标与 Godot 项目图标同源，不再从角色动画帧中随机取图。

## 应用图标

当前图标资产：

| 路径 | 用途 |
| --- | --- |
| `godot_pet/assets/app_icon.png` | Godot 运行时图标，512x512 透明 PNG |
| `packaging/icons/mascotmate-desktop.png` | Linux hicolor launcher 图标，256x256 透明 PNG |

Godot 引用在 `godot_pet/project.godot`：

```ini
config/icon="res://assets/app_icon.png"
```

## Godot export

安装 export templates：

```bash
scripts/setup_godot_export_templates.sh
```

执行正式导出：

```bash
scripts/build_godot_linux.sh --export
```

或：

```bash
GODOT_EXPORT=1 scripts/build_godot_linux.sh
```

导出配置来自：

```text
godot_pet/export_presets.cfg
```

## 跨平台 portable zip

跨平台 zip 使用 Godot export templates 和 PyInstaller helper：

```bash
python3 scripts/setup_dev_environment.py
python3 scripts/build_portable.py --target linux
python3 scripts/build_portable.py --target windows
python3 scripts/build_portable.py --target macos
```

本地通常只构建当前系统对应的 target；三平台产物由 CI 在对应 runner 上构建。

产物位于：

```text
dist/MascotMateDesktop-<platform>.zip
```

## portable bundle 内容

| 路径 | 说明 |
| --- | --- |
| `GodotPetRuntime` | Godot runtime 可执行文件 |
| `MascotMateDesktop` | 启动脚本，设置环境变量并启动项目 |
| `godot_pet/` | Godot 项目 |
| `resource_hd/` | 默认皮肤动作帧 |
| `assets/` | 特效、轻互动和贴边素材 |
| `skin_catalog/` | 皮肤商店精选源和 fallback |
| `skin_store/` | 皮肤商店静态页面 |
| `companion_console/` | 陪伴控制台静态页面 |
| `scripts/pet_helper` | 全局快捷键、截图和剪贴板辅助程序 |
| `scripts/companion_ai_sidecar.py` | 可选 AI 表达 sidecar |

## 发布前检查

建议执行：

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
python3 scripts/validate_skin_catalog.py --check
python3 scripts/run_godot_smoke.py
python3 -m unittest discover tests
scripts/build_godot_linux.sh
```

涉及截图贴图、窗口和快捷键时，还需要在目标桌面环境手动验证 `F1`、`F3`、`F4`、右键菜单、透明窗口和鼠标穿透。
