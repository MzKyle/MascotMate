# 打包模块

## 打包入口

Linux runtime bundle 入口是：

```text
scripts/build_godot_linux.sh
```

跨平台 portable zip 入口是：

```bash
python3 scripts/build_portable.py --target linux
python3 scripts/build_portable.py --target windows
python3 scripts/build_portable.py --target macos
```

本地通常只构建当前系统对应的 target；三平台产物由 GitHub Actions 在对应 runner 上构建。

它会先执行：

```bash
python3 scripts/generate_godot_manifest.py
```

确保 `actions.json` 和当前资源目录一致。

CI 打包前还会运行：

```bash
python -m py_compile scripts/*.py
python -m unittest discover tests
python scripts/generate_godot_manifest.py --check
python scripts/validate_resources.py
python scripts/run_godot_smoke.py
```

资源缺失、动作清单过期、PNG 损坏或 Godot 核心脚本 smoke 失败都会阻断打包。

## portable bundle 流程

默认流程：

1. 准备 Godot runtime
2. 清理并创建 `dist/GodotShinchanPet/`
3. 复制 Godot runtime 为 `GodotPetRuntime`
4. 复制 `godot_pet/`
5. 复制 `resource_hd/` 和 `assets/`
6. 复制 `scripts/pet_helper.py`、`scripts/import_shimeji_skin.py`、`scripts/skin_sdk.py` 和可选的 `scripts/pet_helper`
7. 写入启动脚本 `CrayonShinchanGodotPet`

启动脚本会设置：

```bash
CRAYON_PET_ROOT="$APP_DIR"
CRAYON_PET_TRANSPARENT=1
CRAYON_PET_ALWAYS_ON_TOP=1
CRAYON_PET_BORDERLESS=1
CRAYON_PET_MOUSE_PASSTHROUGH=1
```

然后执行：

```bash
GodotPetRuntime --path godot_pet
```

## Godot export 流程

当传入 `--export` 或 `GODOT_EXPORT=1` 时，脚本会检查 export templates：

```text
~/.local/share/godot/export_templates/<version>/linux_debug.x86_64
~/.local/share/godot/export_templates/<version>/linux_release.x86_64
```

缺失时会提示运行：

```bash
scripts/setup_godot_export_templates.sh
```

导出成功后仍会复制外部资源目录，因为当前项目运行时需要从仓库根、打包根或 macOS `.app` 的上级目录加载资源。

## 三平台 portable zip

`scripts/build_portable.py` 会：

1. 生成 `godot_pet/assets/actions.json`
2. 生成默认皮肤 `godot_pet/assets/skins/classic_shinchan/skin.json`
3. 用 PyInstaller 构建 `pet_helper`
4. 调用 Godot export preset 导出 Linux、Windows 或 macOS
5. 复制 `resource_hd/`、`assets/`、helper、`import_shimeji_skin.py` 和 `skin_sdk.py`
6. 输出 `dist/CrayonShinchanPet-<platform>.zip`

本地私用皮肤只在显式传参时复制，不会进入公开 CI/release：

```bash
python3 scripts/build_portable.py --target linux --private-skins-dir private_skins
```

`private_skins/` 应该包含若干皮肤目录，每个目录都有自己的 `skin.json`。

GitHub Actions 工作流 `.github/workflows/package.yml` 支持手动触发，也会在推送 `v*` 标签时构建三平台 zip artifact。每个平台在打包前都会运行 Python 校验和 Godot headless runtime smoke test。

## desktop entry

`scripts/install_desktop_entry.sh` 会把模板：

```text
packaging/crayon-shinchan-desktop-pet.desktop.in
```

渲染为用户级 desktop entry。它不会写系统目录，不需要 root 权限。

## 常见打包问题

| 问题 | 处理 |
| --- | --- |
| 找不到 Godot | 运行 `scripts/setup_godot.sh` 或设置 `GODOT_BIN` |
| export templates 缺失 | 运行 `scripts/setup_godot_export_templates.sh` |
| 打包后没有全局快捷键 | 确认 `scripts/pet_helper` 已被复制并有可执行权限；macOS 检查辅助功能权限 |
| Linux 截图没有复制到剪贴板 | 安装 `wl-copy` 或 `xclip` |
| 透明窗口异常 | 运行时设置 `CRAYON_PET_SAFE_WINDOW=1` 排查 |
