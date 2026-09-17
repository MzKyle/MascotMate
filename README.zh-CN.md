# 桌宠伙伴

[English](README.md) | [简体中文](README.zh-CN.md)

![桌宠伙伴](docs/assets/cover.png)

桌宠伙伴是一个本地运行的桌面宠物应用。它会在桌面上放一个可互动的动画伙伴，你可以摸摸头、戳一戳、抱起来、轻轻放下、甩飞、拖到屏幕边缘偷看，也可以用它做区域截图、桌面贴图、皮肤管理和低压力陪伴提示。

这个项目面向个人桌面使用：不需要账号，不依赖云端后台，也不强制开启自由聊天。核心运行时由 Godot 驱动，状态和配置都保存在本机。

## 下载

便携版会发布在 GitHub Releases。它不需要安装器：下载对应系统的 ZIP，完整解压，然后从解压后的文件夹里运行应用。

| 系统 | 下载 | 运行 |
| --- | --- | --- |
| Windows x86_64 | [MascotMateDesktop-windows-x86_64.zip](https://github.com/MzKyle/MascotMate/releases/latest/download/MascotMateDesktop-windows-x86_64.zip) | `MascotMateDesktop.exe` |
| macOS universal | [MascotMateDesktop-macos-universal.zip](https://github.com/MzKyle/MascotMate/releases/latest/download/MascotMateDesktop-macos-universal.zip) | `MascotMateDesktop.app` |
| Linux x86_64 | [MascotMateDesktop-linux-x86_64.zip](https://github.com/MzKyle/MascotMate/releases/latest/download/MascotMateDesktop-linux-x86_64.zip) | `MascotMateDesktop` |

[查看全部版本](https://github.com/MzKyle/MascotMate/releases)

请保持解压后的文件和文件夹在一起。MascotMate 运行时会读取随包的 `resource_hd`、`assets`、`skin_catalog`、`skin_store`、`companion_console` 和 `scripts` 目录。macOS 用户也请把 `MascotMateDesktop.app` 留在解压目录里，不要只把 `.app` 单独拖走。

## 快速开始

1. 从上方表格下载与你系统匹配的 ZIP。
2. 完整解压 ZIP。
3. 从解压后的文件夹里运行应用。
4. 右键桌宠，选择 **怎么玩？** 可以随时重播基础提示。

Windows 可能会对未签名的本地构建显示 SmartScreen 提示。macOS 第一次打开时也可能需要你确认允许打开。

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

右键菜单包含散步、投喂、睡觉、唤醒、逗一逗、怎么玩、显示大小、重力开关、皮肤商店、陪伴控制台、截图贴图设置、行为模式、文案语气、清理捣乱物和退出。

## 它能做什么

- 在桌面显示透明、置顶的动画桌宠。
- 支持摸头、戳身体、抱起、轻放、甩飞、贴边偷看。
- 支持安静、活泼、捣乱三种行为模式。
- 气泡文案偏温柔、鼓励、减压，并可选择温柔、元气、安静三种文案语气。
- 支持饭团投喂、鼠标逗一逗等轻互动。
- 支持区域截图、把截图贴到桌面、关闭当前贴图。
- 内置浏览器皮肤商店，可安装精选皮肤，也可辅助导入 Shimeji-ee ZIP 或文件夹。

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

## 故障排查

- 如果桌宠找不到皮肤或素材，请确认你是从完整解压后的便携目录运行，没有只移动可执行文件或 `.app`。
- 如果 Linux 桌面环境对透明窗口支持不稳定，开发者可以用 `CRAYON_PET_SAFE_WINDOW=1` 从源码运行安全窗口模式。
- 如果最新下载链接不可用，请打开 [Releases 页面](https://github.com/MzKyle/MascotMate/releases)，下载最新的对应平台包。

## 开发者

从源码运行：

```bash
python3 scripts/setup_dev_environment.py
scripts/setup_godot.sh
python3 scripts/generate_godot_manifest.py
scripts/run_godot_pet.sh
```

安全窗口模式：

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

构建本地 Linux portable 包并安装用户级启动器：

```bash
scripts/build_godot_linux.sh
scripts/install_desktop_entry.sh
```

常用检查命令：

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
python3 scripts/validate_skin_catalog.py --check
python3 scripts/run_godot_smoke.py
python3 -m unittest discover tests
```

详细文档：

- [开发者文档入口](docs/README.md)
- [从源码运行](docs/guide/run-app.md)
- [安装与打包](docs/guide/package-install.md)
- [架构总览](docs/architecture/README.md)
- [行为系统](docs/modules/behavior.md)
- [截图贴图](docs/modules/screenshot-pins.md)
- [皮肤包规范](docs/sdk/skin-package-spec.md)
- [故障排查](docs/faq/troubleshooting.md)

## 许可与素材

代码使用 [Apache License 2.0](LICENSE)。仓库中的角色相关素材属于粉丝项目素材，请仅在学习、研究和个人本地桌面使用场景中使用；公开发行前请替换为原创或已授权素材。
