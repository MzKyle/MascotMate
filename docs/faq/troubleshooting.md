# 故障排查 FAQ

## 启动时提示找不到 Godot

先运行：

```bash
scripts/setup_godot.sh
```

或指定本机 Godot：

```bash
GODOT_BIN=/path/to/godot4 scripts/run_godot_pet.sh
```

## 透明窗口显示异常

用安全窗口模式确认项目逻辑：

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

如果安全窗口正常，问题通常来自桌面环境对透明窗口、置顶或鼠标穿透的支持差异。

## 鼠标无法点击桌面或桌宠

先关闭鼠标穿透排查：

```bash
CRAYON_PET_MOUSE_PASSTHROUGH=0 scripts/run_godot_pet.sh
```

如果关闭后正常，问题可能在 `Window.mouse_passthrough_polygon` 或当前桌面环境对该能力的实现。

## 动画没更新或新增动作不出现

重新生成动作清单：

```bash
python3 scripts/generate_godot_manifest.py
```

确认对应目录下有 PNG：

```text
resource_hd/<动作目录>/
```

## 高清资源没有生效

运行时从 `resource_hd/` 加载动作帧。确认文件存在后重新生成清单：

```bash
python3 scripts/generate_godot_manifest.py
```

## 全局快捷键不生效

Linux 下先确认当前会话：

```bash
echo "$XDG_SESSION_TYPE"
```

Wayland 下默认不启用全局快捷键。Windows/macOS 下由 `pynput` helper 监听，macOS 可能需要授予辅助功能权限。

再确认依赖：

```bash
python3 --version
python3 scripts/pet_helper.py hotkeys --help
```

如果只想禁用全局快捷键：

```bash
CRAYON_PET_ENABLE_GLOBAL_HOTKEYS=0 scripts/run_godot_pet.sh
```

## `F1` 截图失败

截图默认使用 Godot 内置截图。Linux 如果截图能保存但没有复制到剪贴板，安装剪贴板工具：

```bash
sudo apt-get install -y wl-clipboard xclip
```

如果 Godot 截图不可用，Linux 可安装旧截图兜底工具：

```bash
sudo apt-get install -y kde-spectacle imagemagick
```

## 打包后截图贴图全局快捷键失效

确认打包目录中存在：

```text
dist/MascotMateDesktop/scripts/pet_helper.py
dist/MascotMateDesktop/scripts/pet_helper
```

并且可执行：

```bash
chmod +x dist/MascotMateDesktop/scripts/pet_helper.py
chmod +x dist/MascotMateDesktop/scripts/pet_helper
```

当前构建脚本会自动复制并设置权限。

## Godot export 提示 templates 缺失

安装 export templates：

```bash
scripts/setup_godot_export_templates.sh
```

或者直接使用默认 portable bundle：

```bash
scripts/build_godot_linux.sh
```
