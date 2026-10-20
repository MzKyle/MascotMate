# 状态与配置文件

v1.3 的配置、状态、事件、画像、截图、皮肤和缓存统一写入应用数据目录：

| 平台 | 数据目录 |
| --- | --- |
| Windows | `%APPDATA%\mascotmate-desktop` |
| macOS | `~/Library/Application Support/mascotmate-desktop` |
| Linux | `${XDG_DATA_HOME:-~/.local/share}/mascotmate-desktop` |

下文路径以 Linux 默认目录为例。显式 CLI 路径优先，其次是 `CRAYON_PET_CONFIG_DIR`，最后是平台默认值。旧目录不会自动读取或迁移，旧文件不删除。

## 状态文件

```text
~/.local/share/mascotmate-desktop/state.json
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

## 陪伴事件日志

```text
~/.local/share/mascotmate-desktop/companion_events.json
```

`CompanionEventStore.gd` 的 v2 存储同时保存最近 200 条结构化明细与长期日聚合 `daily`。每次用户或自动事件先写入日聚合，再裁剪明细；日聚合记录事件、用户互动、模式、时段以及照料/陪玩/打扰计数，永久保留。

3/7/30 天分别包含今天及之前 2/6/29 个本地自然日。日期在事件记录时确定，之后不因时区变化重新归档。累计统计由全部日聚合派生，重复刷新不会重复计数。

文件通过 `.tmp` 原子替换，并保留上一次有效的 `.bak`；主文件 JSON 或聚合结构损坏时读取有效备份。主文件和备份均不可用时从空数据启动。写入失败保留内存中的待保存数据及原有文件，可通过 `last_save_error` 检查。


## 陪伴记忆

```text
~/.local/share/mascotmate-desktop/companion_memory.json
```

`CompanionMemory.gd` 会从长期日聚合读取今日计数、近 3 个自然日计数、偏好互动、常用模式/时段、关系熟悉度和最近表达。当前记忆会影响气泡文案选择、主动提示阈值、自动行为权重和非工作时段冷却；不会改变核心状态数值。文件缺失或损坏时会从事件日志重新聚合。

## 长期陪伴画像

```text
~/.local/share/mascotmate-desktop/companion_profile.json
```

`CompanionLongTermProfile.gd` 会保存长期聚合结果，包括常见互动、常用模式、常用时段、照料/陪玩倾向、打扰容忍度和 7/30 天趋势摘要。画像由事件存储的日聚合派生，不再依赖明细去重和裁剪后的日志。当前画像会进入表达上下文、行为适配和控制台快照；只温和影响主动提示阈值、自动行为权重和非工作时段冷却，不改变核心状态数值。

## 陪伴控制台诊断文件

```text
~/.local/share/mascotmate-desktop/companion_debug_snapshot.json
~/.local/share/mascotmate-desktop/companion_scenario_result.json
~/.local/share/mascotmate-desktop/companion_console_command.json
```

浏览器陪伴控制台会读取运行时快照和场景回放结果。快照包含当前状态、行为模式、文案语气、时段、忙碌状态、透明窗口状态、皮肤人格、短期记忆、长期画像、AI health、最近表达来源统计、最近事件和最近一次 decision。

Godot 会在启动、配置/状态变化、场景回放和退出时主动写入快照。陪伴控制台 helper 运行期间，运行时还会每 1 秒刷新一次 `companion_debug_snapshot.json`，供浏览器页面轮询读取；控制台未打开时不会无条件持续写该文件。

控制台命令通过 `companion_console_command.json` 传给 Godot，处理后会删除该命令文件。

## 应用与截图贴图配置

```text
~/.local/share/mascotmate-desktop/config.json
```

保存内容：

| 字段 | 说明 |
| --- | --- |
| `version` | 配置结构版本，目前为 `1` |
| `app.display_scale` | 显示大小，范围 1.0-1.5 |
| `app.gravity_enabled` | 是否开启重力 |
| `app.skin_id` | 当前启用皮肤 ID |
| `app.dialogue_tone` | 气泡文案语气：`gentle`、`short_cute`、`calm` |
| `app.onboarding_version` | 已播放的首次引导版本；旧配置缺失时默认为 `0` |
| `app.behavior_adaptation.enabled` | 是否启用本地行为适配 |
| `app.behavior_adaptation.strength` | 适配强度：`subtle`、`visible`、`bold` |
| `app.ai_expression.enabled` | 是否启用可选 AI 气泡文案 |
| `app.ai_expression.provider` | AI 表达 provider：`local_stub`、`openai_compatible` |
| `app.ai_expression.timeout_ms` | Godot 请求 sidecar 的超时时间，范围 100-5000ms |
| `app.ai_memory_summary.enabled` | 是否启用可选 AI 结构化记忆总结，默认关闭 |
| `app.ai_memory_summary.provider` | AI 记忆总结 provider：`local_stub`、`openai_compatible` |
| `app.ai_memory_summary.timeout_ms` | Godot 请求记忆总结端点的超时时间，范围 100-5000ms |
| `app.ai_memory_summary.min_events` | 自动总结前需要的最近事件数量，范围 1-200 |
| `app.ai_memory_summary.min_interval_seconds` | 自动总结最小间隔，范围 60 秒到 30 天 |
| `shortcuts.screenshot` | 截图快捷键 |
| `shortcuts.paste_pin` | 贴图快捷键 |
| `shortcuts.close_pin` | 关闭贴图快捷键 |
| `screenshot.backend` | 截图后端，默认 `auto` |
| `pins.max_count` | 最大贴图数量，范围 1-3 |

右键菜单中的显示大小、重力开关、皮肤选择、文案语气和“截图贴图设置”会写入这个文件。首次启动引导播放完成后会写入 `app.onboarding_version`；右键“怎么玩？”只重播引导，不改变版本。

截图现在默认使用 Godot 内置截图，Linux 上仅在 Godot 截图不可用时自动兜底到 Spectacle 或 ImageMagick。无效字段会在启动时合并回默认值。

## 截图历史

```text
~/.local/share/mascotmate-desktop/screenshots/
```

截图文件命名格式：

```text
screenshot_<timestamp>_<ticks>.png
clipboard_<timestamp>_<ticks>.png
```

历史最多保留 3 张。超过上限时，旧截图文件会被删除。

## 用户皮肤

```text
~/.local/share/mascotmate-desktop/skins/
```

浏览器皮肤商店和 `scripts/import_shimeji_skin.py` 会把 Shimeji-ee 导入结果写到这个目录。每个皮肤是一个独立目录，包含 `skin.json` 和 `frames/`。

## 清理配置

重置桌宠状态：

```bash
rm -f ~/.local/share/mascotmate-desktop/state.json
```

重置截图贴图设置：

```bash
rm -f ~/.local/share/mascotmate-desktop/config.json
```

清理截图历史：

```bash
rm -rf ~/.local/share/mascotmate-desktop/screenshots
```

清理陪伴事件日志：

```bash
rm -f ~/.local/share/mascotmate-desktop/companion_events.json
```

清理陪伴记忆：

```bash
rm -f ~/.local/share/mascotmate-desktop/companion_memory.json
```

清理长期陪伴画像：

```bash
rm -f ~/.local/share/mascotmate-desktop/companion_profile.json
```

清理陪伴控制台诊断文件：

```bash
rm -f ~/.local/share/mascotmate-desktop/companion_debug_snapshot.json
rm -f ~/.local/share/mascotmate-desktop/companion_scenario_result.json
rm -f ~/.local/share/mascotmate-desktop/companion_console_command.json
```

清理用户导入皮肤：

```bash
rm -rf ~/.local/share/mascotmate-desktop/skins
```
