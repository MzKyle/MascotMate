# 皮肤商店 catalog

皮肤商店有两类数据源：

| `source_type` | 用途 | 下载方式 |
| --- | --- | --- |
| `external_browser` | 第三方 Shimeji 浏览条目，例如 Cachomon SFW 列表 | 只打开原站页面，用户下载后拖入或导入 ZIP |
| `curated_package` | 项目维护、明确允许再分发的精选皮肤包 | 应用内下载、校验 SHA-256、安装并启用 |

默认体验由浏览器版皮肤商店承载：顶部展示随包可直装精选皮肤，下面展示 `external_browser` 条目，让用户能看到真实 Shimeji 皮肤生态。

## 浏览器商店服务

右键“皮肤商店”会启动本地 helper：

```bash
python3 scripts/pet_helper.py skin-store --repo-root . --config-dir ~/.config/mascotmate-desktop --open-browser
```

服务只监听 `127.0.0.1`，启动时生成随机 token。浏览器页面通过本地 API 安装精选皮肤、启用已安装皮肤或打开第三方原站。安装或启用成功后，helper 会写入：

```text
~/.config/mascotmate-desktop/skin_store_command.json
```

Godot 运行时会轮询这个文件并立即切换皮肤。

## Cachomon 浏览索引

运行时会读取 Cachomon SFW 列表的元数据和预览图 URL，但不会镜像、内置或代下载第三方 ZIP。点击“打开原站”会跳到原始详情页，下载完成后可以把 ZIP 拖到皮肤商店窗口，或用“导入 ZIP”安装。

本地缓存位置：

```text
~/.config/mascotmate-desktop/catalog_cache/cachomon/index.json
~/.config/mascotmate-desktop/catalog_cache/cachomon/previews/
```

随包 fallback：

```text
skin_catalog/cachomon_index.json
```

刷新索引：

```bash
python3 scripts/pet_helper.py fetch-cachomon-index --safe --json
```

`external_browser` 条目字段：

```json
{
  "source_type": "external_browser",
  "id": "cachomon-123",
  "name": "Example Shimeji",
  "description": "Open the original Cachomon page to download this Shimeji.",
  "source_url": "https://cachomon.com/shimeji/123",
  "preview_url": "https://cachomon.com/...",
  "artist": "Artist",
  "status": "free",
  "complexity": "Regular",
  "features": ["rarelyclimbs"],
  "downloads": 1234,
  "safe_level": "safe",
  "format": "shimeji-ee"
}
```

`status` 目前会归一化为 `free`、`beta`、`patreon`、`unavailable` 或 `unknown`。这类条目不会进入 ZIP 哈希校验路径，因为应用没有分发其安装包。

## 精选皮肤源

项目维护的精选源地址：

```text
https://raw.githubusercontent.com/MzKyle/Crayon-Shinchan-Desktop-Pat/main/skin_catalog/catalog.json
```

网络不可用或远端格式错误时，运行时会回退到随包复制的本地 `skin_catalog/catalog.json`。精选源只收录明确允许再分发的皮肤。当前随包精选包含两款由 DPets 的 `cat.png` 和 `sprite.png` 转换来的原生皮肤包，署名和许可文件位于 `skin_catalog/notices/dpets/`。

`curated_package` 条目字段：

```json
{
  "source_type": "curated_package",
  "id": "dpets_cat",
  "name": "DPets Cat",
  "description": "A crisp pixel cat companion adapted from the DPets desktop pet sprites.",
  "tags": ["featured", "pixel", "cat", "dpets"],
  "license": {
    "type": "MIT + attribution",
    "summary": "Adapted from DPets sprites by Gustavo dos Santos / Denellyne.",
    "redistributable": true
  },
  "format": "mascotmate_skin_zip",
  "preview": "previews/dpets_cat.png",
  "package": "packages/dpets_cat.zip",
  "sha256": "...",
  "size_bytes": 12345,
  "min_app_version": "1.2.0"
}
```

`preview` 和 `package` 使用相对路径。在线读取时会相对 `catalog.json` 的 URL 解析；本地 fallback 会相对 `skin_catalog/` 目录解析。

## 安装与校验

精选源下载的 ZIP 必须满足：

- 皮肤包小于 100MB。
- `sha256` 与实际文件一致。
- ZIP 内不能包含绝对路径、`..` 路径或符号链接。
- 原生皮肤包必须包含 `skin.json`；Shimeji-ee ZIP 会通过导入器转换。
- `license.redistributable` 必须为 `true`。

校验精选源：

```bash
python3 scripts/validate_skin_catalog.py --check
```

重新下载 DPets 素材并生成随包精选源：

```bash
python3 scripts/fetch_featured_skins.py
```

## 本地调试源

开发时可以覆盖精选源：

```bash
MASCOTMATE_SKIN_CATALOG_URL=http://127.0.0.1:8000/catalog.json scripts/run_godot_pet.sh
```

兼容旧变量名：

```bash
CRAYON_PET_SKIN_CATALOG_URL=http://127.0.0.1:8000/catalog.json scripts/run_godot_pet.sh
```

除 `127.0.0.1` 和 `localhost` 外，HTTP 源会被拒绝；正式远端必须使用 HTTPS。Cachomon 浏览索引不使用这个变量，它由 `fetch-cachomon-index` helper 刷新并写入本地缓存。
