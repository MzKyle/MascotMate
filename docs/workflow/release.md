# 发布流程

## 版本发布前

建议确认工作区：

```bash
git status --short
```

确认动作清单：

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
python3 scripts/validate_skin_catalog.py --check
python3 -m unittest discover tests
python3 -c "import pathlib, py_compile; [py_compile.compile(str(p), doraise=True) for p in pathlib.Path('scripts').glob('*.py')]"
python3 scripts/run_godot_smoke.py
```

检查 README 和文档站：

```bash
cd docs
python3 -m http.server 4173 --bind 127.0.0.1
```

## 打包

跨平台 portable zip：

```bash
python3 scripts/build_portable.py --target linux
python3 scripts/build_portable.py --target windows
python3 scripts/build_portable.py --target macos
```

本地通常只构建当前系统对应的 target；三平台产物由 GitHub Actions 在对应 runner 上构建。

发布 ZIP 名称必须与工作流和 README 保持一致：

```text
MascotMateDesktop-linux-x86_64.zip
MascotMateDesktop-windows-x86_64.zip
MascotMateDesktop-macos-universal.zip
```

包内会包含 `README.txt`；打包脚本会打印包体大小报告。

Linux runtime bundle：

```bash
scripts/build_godot_linux.sh
```

正式 Godot export：

```bash
scripts/setup_godot_export_templates.sh
scripts/build_godot_linux.sh --export
```

## 安装并验证

安装桌面入口：

```bash
scripts/install_desktop_entry.sh
```

运行验证：

```bash
dist/MascotMateDesktop/MascotMateDesktop
```

验收清单：

- 透明窗口正常
- 右键菜单可打开
- 右键“怎么玩？”可重播基础提示
- 首次启动不出现透明窗口/Godot 安全窗口等技术启动气泡
- 显示大小可切换
- 修改显示大小后重启仍保留
- 重力开关生效
- 修改重力开关后重启仍保留
- 行为模式重启后仍回到安静模式
- 抱起、甩飞、落地正常
- 拖到屏幕边缘可进入偷看
- 活泼模式会自动散步或贴边
- 捣乱模式可开始和停止
- `F1`、`F3`、`F4` 在目标系统下可用
- 截图可拖选区域，并能复制图片到剪贴板
- Windows / macOS 产物来自 GitHub Actions artifact，并按同一清单手动验收
- GitHub Release body 含三平台下载表、完整解压说明、macOS 不单独移动 `.app` 的提示，并保留自动生成的 release notes
- macOS 首次全局快捷键可能需要辅助功能权限
- Linux Wayland 下全局快捷键会降级为应用内快捷键

## 开源发布前检查

- 不提交 `dist/`、`tools/`、`godot_pet/.godot/` 等本地产物
- 不提交 IDE 工程文件、虚拟环境和本地构建缓存
- 不提交个人配置目录中的 `state.json`、`config.json` 或截图历史
- 确认 `LICENSE` 为 Apache License 2.0
- 确认第三方素材 `NOTICE.md` 仍在对应目录
- 确认 README 中的仓库链接、文档链接和命令可用
