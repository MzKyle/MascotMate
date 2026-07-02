# 皮肤包规范 v2

`skin.json` 是第三方皮肤包的稳定接口。运行时继续兼容旧 v1 清单；新皮肤建议使用 `schema_version: 2`。

## 目录结构

```text
my-skin/
├── skin.json
├── import_report.json        # 可选，导入器生成
└── frames/
    └── idle/001.png
```

## 必填字段

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 固定为 `2` |
| `id` | 小写字母、数字、`-`、`_` 组成的唯一 ID |
| `name` | UI 显示名 |
| `metadata` | 包版本、作者和兼容等级 |
| `frame_root` | 帧根目录，支持相对路径、`$repo/`、`$config/` |
| `preview` | 相对 `frame_root` 的 PNG 预览图 |
| `license` | 素材授权和再分发说明 |
| `capabilities` | 能力标签到动作候选的映射 |
| `fallbacks` | 能力缺失时的回退关系 |
| `actions` | 动作定义 |

## 元数据与授权

```json
{
  "metadata": {
    "package_version": "1.0.0",
    "authors": [{ "name": "Author" }],
    "compatibility_level": "good",
    "compatibility_score": 82
  },
  "license": {
    "type": "user-provided",
    "summary": "User-provided assets.",
    "redistributable": false
  }
}
```

兼容等级固定为：`excellent`、`good`、`partial`、`minimal`。评分由核心能力覆盖、缺失帧、fallback 使用、镜像补全和导入警告共同决定。

## 能力标签

核心能力必须尽量覆盖：

| 能力 | 运行时场景 |
| --- | --- |
| `resting` | 待机、默认回退 |
| `locomotion` | 地面散步 |
| `falling` | 甩飞、下落 |
| `held` | 长按抱起 |
| `edge` | 墙面吸附、贴边走 |

扩展能力包括：`sleeping`、`waking`、`feeding`、`playful`、`mischief`、`reaction`、`companion`。

候选格式：

```json
{
  "capabilities": {
    "locomotion": [
      { "action": "walk_left", "score": 100, "direction": "left" },
      { "action": "walk_right", "score": 100, "direction": "right" }
    ]
  }
}
```

`direction` 只使用 `left` 或 `right`。运行时会按方向约束给匹配项加权，不匹配项降权。

## 动作字段

每个 action 至少包含：

| 字段 | 说明 |
| --- | --- |
| `name` | 显示名 |
| `resource` | 资源目录 |
| `size` | Godot 显示尺寸 |
| `fps` | 默认帧率 |
| `loop` | 是否循环 |
| `frames` | PNG 帧相对路径 |

可选字段：

| 字段 | 说明 |
| --- | --- |
| `durations_ms` | 逐帧时长，长度必须等于 `frames` |
| `anchors` | 逐帧锚点，长度必须等于 `frames` |
| `velocities` | Shimeji 原始逐帧速度，长度必须等于 `frames` |
| `mirror_x` | 水平镜像播放 |
| `native_edge_pose` | 动作本身已经是墙面/边缘姿态，不再旋转 |
| `source_action` | 原始动作名 |

`anchors` 使用 Shimeji 的图片坐标系。运行时会把当前帧 anchor 映射到角色节点原点，用于减少脚底、墙面和投喂碰撞漂移。

## Fallback

`fallbacks` 指定能力缺失时的回退链。链路不能成环。

```json
{
  "fallbacks": {
    "feeding": "playful",
    "playful": "resting",
    "edge": "locomotion"
  }
}
```

分数低于或等于 `30` 的候选会被视为弱 fallback，并影响兼容评分。
