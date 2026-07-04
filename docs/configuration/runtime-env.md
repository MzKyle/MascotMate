# 运行环境变量

## Godot 准备

| 变量 | 说明 |
| --- | --- |
| `GODOT_BIN` | 指定 Godot 可执行文件。设置后 `setup_godot.sh` 会优先使用它 |
| `GODOT_VERSION` | 指定下载 Godot runtime 或 export templates 的版本 |
| `GODOT_EXPORT` | 设为 `1` 时，`build_godot_linux.sh` 走 Godot export |
| `GODOT_EXPORT_TEMPLATE_DIR` | 自定义 export templates 安装目录 |

示例：

```bash
GODOT_BIN=/opt/godot/Godot_v4.6.3-stable_linux.x86_64 scripts/run_godot_pet.sh
```

## 窗口行为

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CRAYON_PET_SAFE_WINDOW` | `0` | 开启安全窗口模式 |
| `CRAYON_PET_TRANSPARENT` | `1` | 启用透明背景 |
| `CRAYON_PET_ALWAYS_ON_TOP` | `1` | 窗口置顶 |
| `CRAYON_PET_BORDERLESS` | `1` | 无边框窗口 |
| `CRAYON_PET_MOUSE_PASSTHROUGH` | `1` | 鼠标穿透多边形 |

排查透明窗口：

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

排查鼠标穿透：

```bash
CRAYON_PET_MOUSE_PASSTHROUGH=0 scripts/run_godot_pet.sh
```

## 截图贴图

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CRAYON_PET_ENABLE_GLOBAL_HOTKEYS` | `1` | 是否启动跨平台全局快捷键辅助进程 |
| `PYTHON` | 自动查找 | 开发模式下指定用于启动 `pet_helper.py` 的 Python |

关闭全局快捷键：

```bash
CRAYON_PET_ENABLE_GLOBAL_HOTKEYS=0 scripts/run_godot_pet.sh
```

这不会禁用应用内快捷键。窗口聚焦时，`F1`、`F3`、`F4` 仍可由 Godot 输入系统处理。

## 皮肤商店精选源

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MASCOTMATE_SKIN_CATALOG_URL` | GitHub raw 精选源 | 覆盖皮肤商店读取的在线 `catalog.json` |
| `CRAYON_PET_SKIN_CATALOG_URL` | 空 | 旧变量名兼容，优先级低于 `MASCOTMATE_SKIN_CATALOG_URL` |

正式远端必须使用 HTTPS。开发调试时允许 `http://127.0.0.1` 或 `http://localhost`：

```bash
MASCOTMATE_SKIN_CATALOG_URL=http://127.0.0.1:8000/catalog.json scripts/run_godot_pet.sh
```

这个变量只影响可应用内下载的精选源。Cachomon/Shimeji 浏览索引由 helper 写入 `~/.config/mascotmate-desktop/catalog_cache/cachomon/index.json`，应用只打开原站页面，不代下载第三方 ZIP。

## AI 表达增强

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MASCOTMATE_AI_EXPRESSION_URL` | `http://127.0.0.1:8765` | Godot 请求本地 AI expression sidecar 的地址 |
| `MASCOTMATE_OPENAI_COMPATIBLE_URL` | 空 | `openai_compatible` provider 的 Chat Completions 兼容 endpoint |
| `MASCOTMATE_OPENAI_COMPATIBLE_API_KEY` | 空 | `openai_compatible` provider 的 API key |
| `MASCOTMATE_OPENAI_COMPATIBLE_MODEL` | `gpt-4o-mini` | `openai_compatible` provider 使用的模型名 |

启动本地 stub sidecar：

```bash
python3 scripts/pet_helper.py companion-ai-sidecar --provider local_stub
```

接入本地 OpenAI-compatible 服务：

```bash
MASCOTMATE_OPENAI_COMPATIBLE_URL=http://127.0.0.1:11434/v1/chat/completions \
MASCOTMATE_OPENAI_COMPATIBLE_API_KEY=local \
MASCOTMATE_OPENAI_COMPATIBLE_MODEL=your-local-model \
python3 scripts/pet_helper.py companion-ai-sidecar --provider openai_compatible
```

接入平台 key：

```bash
MASCOTMATE_OPENAI_COMPATIBLE_URL=https://your-provider.example/v1/chat/completions \
MASCOTMATE_OPENAI_COMPATIBLE_API_KEY=... \
MASCOTMATE_OPENAI_COMPATIBLE_MODEL=... \
python3 scripts/pet_helper.py companion-ai-sidecar --provider openai_compatible
```

AI 表达默认关闭。开启后也只生成气泡文案；sidecar 不可用、超时、HTTP 错误、坏 JSON、超长输出或返回不合规时会使用本地表达库。API key 只从环境变量读取，不写入 `config.json`。
