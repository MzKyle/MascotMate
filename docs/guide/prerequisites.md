# 环境依赖

## 基础环境

推荐环境：

| 依赖 | 推荐版本 | 说明 |
| --- | --- | --- |
| Windows / macOS / Linux | 当前桌面系统 | 跨平台截图贴图和 portable zip 打包 |
| Godot | 4.6.x | `scripts/setup_godot.sh` 会查找 `GODOT_BIN`、PATH 或本地 `tools/godot/`；自动下载只覆盖 Linux portable runtime |
| Python | 3.10+ | 资源处理脚本、开发模式 helper 和打包 |
| Bash | 系统自带 | 运行、打包、安装 desktop entry |
| pip | 最新稳定版 | 安装图片处理依赖 |

安装 Python 依赖：

```bash
python3 -m pip install -r requirements.txt
```

`requirements.txt` 用于资源生成、开发模式 helper 和打包。正式 portable zip 会内置 helper 可执行文件。

## Godot 准备

`scripts/setup_godot.sh` 会按下面顺序寻找 Godot：

1. `GODOT_BIN` 环境变量指定的可执行文件
2. 系统 PATH 中的 `godot4` 或 `godot`
3. `tools/godot/` 下已经下载的 Godot portable 二进制
4. 在 Linux 下从 Godot GitHub Release 下载 `GODOT_VERSION` 指定版本

Windows/macOS 本地打包通常需要先把 Godot 放入 PATH，或显式设置 `GODOT_BIN`。GitHub Actions 的跨平台打包使用 `scripts/setup_godot_ci.py` 准备对应 runner 的 Godot。

手动准备：

```bash
scripts/setup_godot.sh
```

默认版本由脚本中的 `GODOT_VERSION` 决定，目前是 `4.6.3-stable`。如需指定版本：

```bash
GODOT_VERSION=4.6.3-stable scripts/setup_godot.sh
```

## Linux 桌面依赖

透明窗口、置顶窗口和鼠标穿透由 Godot / 桌面环境共同支持。X11 通常兼容性更好；Wayland 会因合成器策略不同而出现差异。

截图贴图默认使用 Godot 内置截图。Linux 如果需要复制图片到剪贴板，建议安装 `wl-copy` 或 `xclip`：

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip wl-clipboard xclip
```

Linux 上 Godot 截图不可用时仍会自动尝试 Spectacle 或 ImageMagick：

```bash
sudo apt-get install -y kde-spectacle imagemagick
```

全局快捷键由 `scripts/pet_helper.py` 提供。Linux/X11 使用 `libX11`，Windows/macOS 使用 `pynput`；Wayland 下默认不启用全局快捷键，但应用窗口聚焦时仍保留应用内快捷键。

## 可选打包依赖

Linux 本地 portable runtime bundle 不需要 Godot export templates，会直接复制 Godot runtime 和项目资源。发布用跨平台 portable zip 走 Godot export preset，因此需要对应平台的 export templates；CI 会在 runner 上准备。

如果要使用 Godot 正式 export：

```bash
scripts/setup_godot_export_templates.sh
```

脚本会下载并安装 Linux export templates 到：

```text
~/.local/share/godot/export_templates/<version>
```
