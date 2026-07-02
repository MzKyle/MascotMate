# 状态与配置文件

运行时数据写入用户配置目录：

```text
~/.config/crayon-shinchan-desktop-pet/
```

## 状态文件

```text
~/.config/crayon-shinchan-desktop-pet/state.json
```

示例：

```json
{
  "version": 2,
  "mood": 70,
  "hunger": 60,
  "energy": 80,
  "affection": 30,
  "last_decay_at": 1761998400,
  "memory": {
    "last_interaction_at": 0,
    "last_interaction_kind": "",
    "last_feed_at": 0,
    "last_play_at": 0,
    "last_prompt_at": 0,
    "last_action_at": 0,
    "interaction_counts": {}
  }
}
```

四个核心数值范围固定为 0-100。`StateStore.gd` 会在读取和写入时做边界保护；旧版只有四个数值的状态文件会自动补齐为 v2。

行为脑 tick 时会按时间段做被动衰减：清醒时饥饿缓慢上升、体力缓慢下降；休息时段体力恢复、饥饿慢升。离线补算最多 8 小时，避免长时间未启动后状态一次性打穿。

行为模式不保存。每次启动都会回到安静模式。

## 应用与截图贴图配置

```text
~/.config/crayon-shinchan-desktop-pet/config.json
```

保存内容：

| 字段 | 说明 |
| --- | --- |
| `version` | 配置结构版本，目前为 `1` |
| `app.display_scale` | 显示大小，范围 1.0-1.5 |
| `app.gravity_enabled` | 是否开启重力 |
| `app.skin_id` | 当前启用皮肤 ID |
| `shortcuts.screenshot` | 截图快捷键 |
| `shortcuts.paste_pin` | 贴图快捷键 |
| `shortcuts.close_pin` | 关闭贴图快捷键 |
| `screenshot.backend` | 截图后端，默认 `auto` |
| `pins.max_count` | 最大贴图数量，范围 1-3 |

右键菜单中的显示大小、重力开关、皮肤选择和“截图贴图设置”会写入这个文件。

截图现在默认使用 Godot 内置截图，Linux 上仅在 Godot 截图不可用时自动兜底到 Spectacle 或 ImageMagick。无效字段会在启动时合并回默认值。

## 截图历史

```text
~/.config/crayon-shinchan-desktop-pet/screenshots/
```

截图文件命名格式：

```text
screenshot_<timestamp>_<ticks>.png
clipboard_<timestamp>_<ticks>.png
```

历史最多保留 3 张。超过上限时，旧截图文件会被删除。

## 用户皮肤

```text
~/.config/crayon-shinchan-desktop-pet/skins/
```

皮肤管理窗口和 `scripts/import_shimeji_skin.py` 会把 Shimeji-ee 导入结果写到这个目录。每个皮肤是一个独立目录，包含 `skin.json` 和 `frames/`。

## 清理配置

重置桌宠状态：

```bash
rm -f ~/.config/crayon-shinchan-desktop-pet/state.json
```

重置截图贴图设置：

```bash
rm -f ~/.config/crayon-shinchan-desktop-pet/config.json
```

清理截图历史：

```bash
rm -rf ~/.config/crayon-shinchan-desktop-pet/screenshots
```

清理用户导入皮肤：

```bash
rm -rf ~/.config/crayon-shinchan-desktop-pet/skins
```
