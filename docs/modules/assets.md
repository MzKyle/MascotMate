# 素材与动作

## 资源目录

| 路径 | 说明 |
| --- | --- |
| `resource_hd/` | 运行时动作帧 |
| `godot_pet/assets/app_icon.png` | Godot 运行时图标，512x512 透明 PNG |
| `packaging/icons/mascotmate-desktop.png` | Linux desktop launcher 图标，256x256 透明 PNG |
| `godot_pet/assets/skins/` | 内置皮肤清单 |
| `skin_catalog/` | 皮肤商店本地 fallback、Cachomon 浏览索引、精选预览、精选 ZIP 和授权 notice |
| `skin_store/` | 浏览器版皮肤商店静态 HTML/CSS/JS |
| `~/.config/mascotmate-desktop/skins/` | 用户导入皮肤 |
| `assets/effects/` | 爱心、闪光、波纹等互动特效 |
| `assets/games/` | 饭团等轻互动素材 |
| `assets/character/` | 贴边偷看图和来源说明 |
| `assets/character/mischief/` | 捣乱动作候选素材和来源说明 |

第三方素材来源见对应目录下的 `NOTICE.md`。

## 应用图标

应用图标是独立资产，不再从默认角色动画帧中截取。

| 路径 | 说明 |
| --- | --- |
| `godot_pet/assets/app_icon.png` | Godot 项目图标，供运行时窗口和导出读取 |
| `packaging/icons/mascotmate-desktop.png` | Linux hicolor 图标，供 `install_desktop_entry.sh` 安装 |

两者同源，当前是原创小狐狸头像透明 PNG。修改图标时要同时更新这两个文件，并确认 `godot_pet/project.godot` 仍指向 `res://assets/app_icon.png`。

## 动作与皮肤清单

旧动作清单位于：

```text
godot_pet/assets/actions.json
```

默认皮肤清单位于：

```text
godot_pet/assets/skins/classic_shinchan/skin.json
```

二者都由 `scripts/generate_godot_manifest.py` 生成。`actions.json` 继续兼容旧资源管线；`skin.json` 是运行时优先使用的皮肤包接口。

完整第三方皮肤接口见：

- [皮肤包规范 v2](../sdk/skin-package-spec.md)
- [皮肤商店 catalog](../sdk/skin-catalog.md)
- [Shimeji-ee 导入](../sdk/shimeji-import.md)

每个动作包含：

| 字段 | 说明 |
| --- | --- |
| `name` | 中文动作名 |
| `resource` | 对应资源目录 |
| `size` | Godot 中的显示尺寸 |
| `fps` | 播放帧率 |
| `loop` | 是否循环 |
| `loop_start` | 循环起始帧 |
| `next_action` | 非循环动作结束后的下一个动作 |
| `frames` | PNG 帧相对路径列表 |
| `durations_ms` | 可选，逐帧时长，Shimeji 导入资源会使用 |
| `anchors` | 可选，逐帧锚点，Shimeji 导入资源会使用 |
| `velocities` | 可选，逐帧速度，供导入报告和后续行为调优使用 |
| `used_rects` | 可选，逐帧非透明区域 `[x, y, width, height]`，用于运行时碰撞和点击区域缓存 |

每个皮肤包含：

| 字段 | 说明 |
| --- | --- |
| `id` | 皮肤 ID |
| `name` | 显示名 |
| `schema_version` | v2 皮肤规范版本；旧皮肤缺省按 v1 兼容 |
| `metadata` | 包版本、作者、兼容等级和评分 |
| `preview` | 预览帧 |
| `frame_root` | 帧根目录，支持 `$repo/` |
| `license` | 素材来源和授权说明 |
| `source` | 导入来源，例如 Shimeji-ee 的 image set 和 XML 路径 |
| `behavior_profile` | 可选，皮肤自己的活泼/捣乱行为权重 |
| `capabilities` | `resting`、`locomotion`、`falling`、`held` 等能力到动作候选的映射 |
| `fallbacks` | 能力缺失时的回退关系 |
| `actions` | 皮肤内动作定义 |

## 当前动作

| 动作 ID | 动作名 | 资源目录 |
| --- | --- | --- |
| `idle` | 闲置 | `xianzhi` |
| `walk_left` | 向左散步 | `sanbu/zuo` |
| `walk_right` | 向右散步 | `sanbu/you` |
| `mischief_grab` | 费力抢鼠标 | `mischief_grab` |
| `fall` | 下落 | `xialuo` |
| `exercise` | 运动 | `yundong` |
| `eat` | 吃饭 | `eat` |
| `sleep` | 睡觉 | `sleep` |
| `wake` | 唤醒 | `waken` |
| `pipi` | 屁屁舞 | `pipi` |
| `transform` | 动感光波 | `xiandanchaoren` |
| `snack` | 偷吃宵夜 | `snack` |
| `meet` | 见到小白 | `meet` |
| `xiaobai` | 小白 | `xiaobai` |

## 高清资源生成

从外部源生成高清副本：

```bash
python3 scripts/generate_hd_assets.py --source /path/to/source --output resource_hd --scale 3 --force
```

运行时加载路径：

```text
resource_hd/<action_frame>
```

瘦身规则是：所有动作帧都整理到 `resource_hd/`。如果暂时只有较低清晰度的素材，也放在对应动作目录中，后续用同名高清帧替换即可。

## 贴边与捣乱素材

重新生成贴边偷看图：

```bash
python3 scripts/generate_peek_assets.py --source /path/to/source.png
```

重新生成捣乱动作帧：

```bash
python3 scripts/generate_mischief_grab_assets.py --source /path/to/source.png
python3 scripts/generate_godot_manifest.py
```

修改动作资源后一定要重新生成 `actions.json`，否则 Godot 仍会按旧清单加载。

## Shimeji-ee 导入

导入 Shimeji-ee zip 或已解压目录：

```bash
python3 scripts/import_shimeji_skin.py /path/to/shimeji.zip
python3 scripts/import_shimeji_skin.py /path/to/shimeji-folder
```

导入器会识别 `img/[NAME]`、全局 `conf/actions.xml` 和皮肤私有 `conf/actions.xml`，把原始动作保留为皮肤动作，并按素材语义归类到能力标签。缺失能力会通过 fallback 使用最接近的动作，走路方向缺失时会生成镜像动作。

导入器还会读取 `behaviors.xml`，生成 `behavior_profile` 和 `import_report.json`。报告包含动作数、帧数、核心能力覆盖、兼容评分、失败帧、镜像动作和解析警告。机器可读输出：

```bash
python3 scripts/import_shimeji_skin.py /path/to/shimeji.zip --json-report
```

真实 Shimeji 包不提交进仓库。需要批量测试时使用外置清单：

```bash
python3 scripts/run_shimeji_corpus.py /path/to/shimeji_corpus.json
```

## 资源校验

发布前检查动作清单和 PNG 资源：

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
```

校验会确认动作非空、帧路径安全、帧文件存在、PNG 可读取、默认皮肤能力引用有效，并检查 `resource_hd/` 中没有未被动作清单引用的 PNG。
