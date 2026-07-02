# Shimeji-ee 导入

导入器把 Shimeji-ee zip 或解压目录转换为 v2 皮肤包。

```bash
python3 scripts/import_shimeji_skin.py /path/to/shimeji.zip
python3 scripts/import_shimeji_skin.py /path/to/shimeji-folder --json-report
```

默认输出到：

```text
~/.config/mascotmate-desktop/skins/
```

## 支持范围

导入器会识别：

- `img/[NAME]` 或直接包含 `shime*.png` 的图片集
- 图片集私有 `conf/actions.xml`
- 全局 `conf/actions.xml`
- 图片集私有或全局 `conf/behaviors.xml`

`actions.xml` 中的 `Action/Pose` 会转换为 action。导入器保留：

- `Image` -> `frames`
- `Duration` -> `durations_ms`
- `ImageAnchor` -> `anchors`
- `Velocity` -> `velocities`
- 动作名 -> `source_action`
- PNG alpha bbox -> `used_rects`

缺少方向动作时会生成 `mirror_x` 镜像动作。墙面、天花板和边缘动作会标记 `native_edge_pose`。导入器会在复制帧时预计算非透明区域，减少运行时切动作时的图片扫描。

## 行为映射

`behaviors.xml` 会映射为 `behavior_profile`，用于活泼/捣乱模式的运行时权重。

| Shimeji 行为名关键词 | 映射 |
| --- | --- |
| `walk`、`run`、`crawl` | `walk` |
| `stand`、`sit`、`lie`、`look`、`face`、`sprawl` | `idle` |
| `wall`、`ceiling`、`edge`、`climb`、`grab` | `edge` |
| `throw`、`pull`、`split`、`chase`、`ie` | `mischief` |

Shimeji 条件表达式、IE 窗口交互、繁殖/分裂状态机不会完整复刻。相关条件会进入导入报告的 `warnings`。

## 导入报告

每个导入皮肤目录都会写入：

```text
import_report.json
```

主要字段：

| 字段 | 说明 |
| --- | --- |
| `action_count` | 导入动作数量 |
| `frame_count` | 可用 PNG 帧数量 |
| `capability_coverage` | 核心能力覆盖 |
| `missing_capabilities` | 缺失能力 |
| `generated_mirrors` | 自动生成的镜像动作 |
| `failed_frames` | 找不到或无法读取的帧 |
| `behavior_mapping` | Shimeji 行为到本项目行为的映射 |
| `compatibility_score` | 兼容分数 |
| `compatibility_level` | `excellent` / `good` / `partial` / `minimal` |
| `warnings` / `errors` | 解析和校验结果 |

`--json-report` 会把导入路径和报告输出到 stdout，供 UI 或自动化脚本消费。

## 外置兼容语料

真实 Shimeji 包可能有版权和体积限制，仓库不提交第三方素材。使用外置清单运行兼容测试：

```bash
cp tests/compat/shimeji_corpus.example.json /tmp/shimeji_corpus.json
python3 scripts/run_shimeji_corpus.py /tmp/shimeji_corpus.json
```

清单支持本地路径或 URL、`sha256` 和最低分：

```json
{
  "skins": [
    {
      "name": "Local sample",
      "path": "/absolute/path/to/shimeji.zip",
      "min_score": 45
    }
  ]
}
```
