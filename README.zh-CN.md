# 桌宠伙伴

[English](README.md) | [简体中文](README.zh-CN.md)

![桌宠伙伴](docs/assets/cover.png)

桌宠伙伴是一个本地运行的桌面宠物应用。它会在桌面上放一个可互动的动画伙伴，你可以摸摸头、戳一戳、抱起来、轻轻放下、甩飞、拖到屏幕边缘偷看，也可以用它做区域截图和桌面贴图。

这个项目面向个人桌面使用：不需要账号，不依赖云端后台，也不强制开启自由聊天。核心运行时由 Godot 驱动，状态和配置都保存在本机。

## 它能做什么

- 在桌面显示透明、置顶的动画桌宠。
- 支持摸头、戳身体、抱起、轻放、甩飞、贴边偷看。
- 支持安静、活泼、捣乱三种行为模式。
- 气泡文案偏温柔、鼓励、减压，并可选择温柔、元气、安静三种文案语气。
- 支持饭团投喂、鼠标逗一逗等轻互动。
- 支持区域截图、把截图贴到桌面、关闭当前贴图。
- 内置浏览器皮肤商店，可安装精选皮肤，也可辅助导入 Shimeji-ee ZIP 或文件夹。
- Linux 下可构建本地 portable bundle，并安装用户级应用启动器。

## 快速启动

在项目根目录执行：

```bash
python3 scripts/setup_dev_environment.py
scripts/setup_godot.sh
python3 scripts/generate_godot_manifest.py
scripts/run_godot_pet.sh
```

如果你的桌面环境对透明窗口或鼠标穿透支持不稳定，先用安全窗口模式：

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

## Linux 本地安装

构建 portable 运行包并安装用户级启动器：

```bash
scripts/build_godot_linux.sh
scripts/install_desktop_entry.sh
```

之后可以在应用启动器中打开 **MascotMate Desktop**，也可以直接运行：

```bash
dist/MascotMateDesktop/MascotMateDesktop
```

安装位置：

```text
~/.local/share/applications/mascotmate-desktop.desktop
~/.local/share/icons/hicolor/256x256/apps/mascotmate-desktop.png
```

## 基本操作

| 操作 | 效果 |
| --- | --- |
| 点击头部 | 摸摸头 |
| 点击身体 | 轻轻戳一下 |
| 长按约 350ms | 抱起 |
| 慢速释放 | 轻轻放下 |
| 快速释放 | 甩飞 |
| 拖到屏幕边缘释放 | 进入贴边偷看 |
| 偷看时点击 | 从边缘出来 |
| 双击 | 开始逗一逗 |
| 鼠标滚轮 | 查看心情、饥饿、体力、亲密度 |
| 右键 | 打开菜单 |

右键菜单包含散步、投喂、睡觉、唤醒、逗一逗、显示大小、重力开关、皮肤商店、陪伴控制台、截图贴图设置、行为模式、文案语气、清理捣乱物和退出。

## 截图贴图

默认快捷键：

| 快捷键 | 效果 |
| --- | --- |
| `F1` | 选择屏幕区域并保存/复制截图 |
| `F3` | 把最近截图贴到桌面，或在最近截图之间轮换 |
| `F4` | 关闭当前贴图 |

截图贴图设置可以从右键菜单打开。

## 陪伴行为

桌宠会维护一组本地状态：心情、饥饿、体力、亲密度。它会根据近期互动和长期聚合偏好，低频地给出投喂或休息陪玩的提示。

行为边界是明确的：

- 安静模式尽量不主动移动，只保留低频照料提示。
- 活泼模式会散步、闲置、贴边、邀请玩一下或显示小特效。
- 捣乱模式只是“费力抢鼠标”的视觉演出，不会移动或锁定系统鼠标。
- 可选 AI 表达默认关闭；开启后也只影响气泡文案，不改变行为和状态。

## 皮肤

内置皮肤兼容项目原有动画资源。皮肤商店可以安装随包精选皮肤，也可以把 Shimeji-ee ZIP 或文件夹导入为本地皮肤。

用户导入皮肤保存在：

```text
~/.config/mascotmate-desktop/skins/
```

## 本地数据

运行数据写入：

```text
~/.config/mascotmate-desktop/
```

这里包含应用配置、状态、截图历史、陪伴记忆摘要、诊断快照和导入皮肤。

## 开发者文档

详细文档面向维护者和开发者：

- [开发者文档入口](docs/README.md)
- [从源码运行](docs/guide/run-app.md)
- [安装与打包](docs/guide/package-install.md)
- [架构总览](docs/architecture/README.md)
- [行为系统](docs/modules/behavior.md)
- [截图贴图](docs/modules/screenshot-pins.md)
- [皮肤包规范](docs/sdk/skin-package-spec.md)
- [故障排查](docs/faq/troubleshooting.md)

## 开发校验

常用检查命令：

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
python3 scripts/validate_skin_catalog.py --check
python3 scripts/run_godot_smoke.py
python3 -m unittest discover tests
```

## 许可与素材

代码使用 [Apache License 2.0](LICENSE)。仓库中的角色相关素材属于粉丝项目素材，请仅在学习、研究和个人本地桌面使用场景中使用；公开发行前请替换为原创或已授权素材。
