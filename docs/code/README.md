# 代码导读

## 从哪里开始读

如果只想理解运行时，建议从：

```text
godot_pet/scripts/Main.gd
```

开始。它会把所有核心脚本创建出来，并连接信号。

如果想改某类能力：

| 目标 | 入口文件 |
| --- | --- |
| 改窗口透明、菜单、模式、偷看 | `Main.gd` |
| 改动画尺寸、帧加载、可见区域 | `PetSprite.gd` |
| 改重力、反弹、贴边 | `PetPhysics.gd` |
| 改单击、双击、长按、甩飞 | `InteractionController.gd` |
| 改自动行为概率 | `BehaviorBrain.gd` |
| 改投喂或接球小游戏 | `MiniGames.gd` |
| 改心情等状态 | `StateStore.gd` |
| 改截图贴图 | `ScreenshotPins.gd`、`PinImageWindow.gd`、`ScreenshotSettingsWindow.gd` |
| 改全局快捷键或图片剪贴板 | `scripts/pet_helper.py` |
| 改资源动作 | `scripts/generate_godot_manifest.py` |
| 改打包 | `scripts/build_godot_linux.sh` |

## 信号风格

Godot 脚本间尽量用信号连接，而不是彼此深度调用。`Main.gd` 是少数知道所有模块的对象，这让各模块可以保持职责清楚。

## 外部资源路径

运行脚本会设置：

```bash
CRAYON_PET_ROOT=<repo root>
```

打包后的启动脚本会设置：

```bash
CRAYON_PET_ROOT=<dist/MascotMateDesktop>
```

因此资源加载代码要优先基于 `repo_root` 拼接路径，而不是假设当前工作目录。
