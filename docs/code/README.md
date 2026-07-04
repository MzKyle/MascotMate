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
| 改行为规则和适配 | `CompanionBehaviorPolicy.gd` |
| 改本地气泡文案 | `CompanionExpressionBank.gd` |
| 改 intent 到气泡/动作/特效的映射 | `CompanionExpressionResolver.gd` |
| 改 AI 表达请求和兜底 | `CompanionAIExpressionClient.gd`、`scripts/companion_ai_sidecar.py` |
| 改陪伴事件、短期记忆、长期画像 | `CompanionEventStore.gd`、`CompanionMemory.gd`、`CompanionLongTermProfile.gd` |
| 改投喂或逗一逗轻互动 | `MiniGames.gd` |
| 改心情等状态 | `StateStore.gd` |
| 改截图贴图 | `ScreenshotPins.gd`、`PinImageWindow.gd`、`ScreenshotSettingsWindow.gd` |
| 改皮肤选择、皮肤商店、Shimeji 导入 | `SkinManager.gd`、`SkinStoreBridge.gd`、`scripts/skin_store_server.py`、`scripts/import_shimeji_skin.py` |
| 改陪伴控制台 | `CompanionConsoleBridge.gd`、`companion_console/`、`scripts/skin_store_server.py` |
| 改全局快捷键或图片剪贴板 | `scripts/pet_helper.py` |
| 改资源动作 | `scripts/generate_godot_manifest.py` |
| 改应用/launcher 图标 | `godot_pet/assets/app_icon.png`、`packaging/icons/mascotmate-desktop.png`、`godot_pet/project.godot` |
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
