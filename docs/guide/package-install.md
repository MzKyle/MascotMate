# 安装与打包

## portable bundle

默认 Linux runtime 打包方式不依赖 Godot export templates。它会把 Godot runtime、Godot 项目、资源目录、素材目录和跨平台 helper 源码复制到 `dist/MascotMateDesktop/`。

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

portable bundle 的优点是稳定、简单、无需额外安装 export templates；缺点是产物体积会更大。

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

三平台 portable zip 使用 Godot export templates 和 PyInstaller helper：

```bash
python3 scripts/setup_dev_environment.py
python3 scripts/build_portable.py --target linux
python3 scripts/build_portable.py --target windows
python3 scripts/build_portable.py --target macos
```

本地通常只构建当前系统对应的 target；三平台产物由 GitHub Actions 在对应 runner 上构建。

产物位于：

```text
dist/MascotMateDesktop-<platform>.zip
```

## 桌面入口

打包完成后安装用户级 desktop entry：

```bash
scripts/install_desktop_entry.sh
```

安装位置：

```text
~/.local/share/applications/mascotmate-desktop.desktop
~/.local/share/icons/hicolor/256x256/apps/mascotmate-desktop.png
```

图标会从 `resource_hd/xianzhi/` 里取第一张 PNG。

## 打包内容

portable bundle 主要包含：

| 路径 | 说明 |
| --- | --- |
| `GodotPetRuntime` | Godot runtime 可执行文件 |
| `MascotMateDesktop` | 启动脚本，设置环境变量并启动项目 |
| `godot_pet/` | Godot 项目 |
| `resource_hd/` | 高清动作帧 |
| `assets/` | 特效、轻互动和偷看素材 |
| `scripts/pet_helper` | 全局快捷键和图片剪贴板辅助程序 |
| `scripts/pet_helper.py` | helper 源码兜底 |

## 发布前检查

发布前建议执行：

```bash
python3 scripts/generate_godot_manifest.py
scripts/build_godot_linux.sh
```

如果改过截图贴图功能，还建议在目标系统下确认：

```bash
dist/MascotMateDesktop/MascotMateDesktop
```

然后验证 `F1`、`F3`、`F4`、区域截图、图片剪贴板和右键菜单中的“截图贴图设置”。
