# 在线精选皮肤源

皮肤管理窗口会优先读取项目维护的在线精选源：

```text
https://raw.githubusercontent.com/MzKyle/Crayon-Shinchan-Desktop-Pat/main/skin_catalog/catalog.json
```

网络不可用或远端格式错误时，运行时会回退到随包复制的本地 `skin_catalog/catalog.json`。精选源只收录明确允许再分发的皮肤；第三方网站上的皮肤仍通过“导入 ZIP/文件夹”由用户自行安装。

## catalog.json

当前 schema 版本为 1：

```json
{
  "schema_version": 1,
  "updated_at": "2026-07-03",
  "skins": [
    {
      "id": "mint_buddy",
      "name": "Mint Buddy",
      "description": "A calm mint desktop companion.",
      "tags": ["sample", "fresh"],
      "license": {
        "type": "CC0-1.0",
        "summary": "Original procedural sample skin.",
        "redistributable": true
      },
      "format": "mascotmate_skin_zip",
      "preview": "previews/mint_buddy.png",
      "package": "packages/mint_buddy.zip",
      "sha256": "...",
      "size_bytes": 12345,
      "min_app_version": "1.2.0"
    }
  ]
}
```

`preview` 和 `package` 使用相对路径。在线读取时会相对 `catalog.json` 的 URL 解析；本地 fallback 会相对 `skin_catalog/` 目录解析。

## 安装与校验

在线下载的 ZIP 必须满足：

- 皮肤包小于 100MB。
- `sha256` 与实际文件一致。
- ZIP 内不能包含绝对路径、`..` 路径或符号链接。
- 原生皮肤包必须包含 `skin.json`；Shimeji-ee ZIP 会通过导入器转换。

校验精选源：

```bash
python3 scripts/validate_skin_catalog.py --check
```

重新生成仓库内示例精选源：

```bash
python3 scripts/generate_sample_skin_catalog.py
```

## 本地调试源

开发时可以覆盖在线源：

```bash
MASCOTMATE_SKIN_CATALOG_URL=http://127.0.0.1:8000/catalog.json scripts/run_godot_pet.sh
```

兼容旧变量名：

```bash
CRAYON_PET_SKIN_CATALOG_URL=http://127.0.0.1:8000/catalog.json scripts/run_godot_pet.sh
```

除 `127.0.0.1` 和 `localhost` 外，HTTP 源会被拒绝；正式远端必须使用 HTTPS。
