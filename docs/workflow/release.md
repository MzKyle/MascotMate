# v1.3 稳定版发布流程

## 本地检查

```bash
python scripts/release_version.py --tag v1.3.0
python scripts/generate_godot_manifest.py --check
python scripts/validate_resources.py
python scripts/validate_skin_catalog.py --check
python -m unittest discover tests
python scripts/run_godot_smoke.py
```

`godot_pet/project.godot` 是版本源，Windows 文件版本为 `X.Y.Z.0`，macOS 为 `X.Y.Z`。修改版本时同步 export preset，检查不一致就阻止打包。发布源码必须已经提交，工作区不能存在未提交改动。

## 构建与验收候选包

主分支推送或手动运行 **Package candidates**（`.github/workflows/package.yml`）都会构建并验收候选包。推送与项目版本一致的 `v*` tag 时，工作流在 Windows/Linux 最终 ZIP 都通过验收后，直接发布同一批文件并标记为 Latest。

Windows/Linux 任务先检查源码，再导出公开 ZIP；对最终 ZIP 重新解压，使用独立的中文、空格目录和全新数据目录验收。检查包内文件哈希、皮肤分发标记、冻结 helper、皮肤导入、商店/控制台 HTTP 服务，以及实际桌面上的透明窗口、菜单、拖拽、甩飞、四方向偷看、设置持久化、截图选区、剪贴板与贴图窗口。Linux 使用 Xvfb、Openbox、picom 与 xclip；Windows 使用 runner 的桌面会话。此自动验收不覆盖系统级全局快捷键与人工视觉检查。

本机等价步骤（设置好 `GODOT_BIN`，并在对应系统运行）：

```bash
python scripts/build_portable.py --target windows
python scripts/verify_package.py dist/MascotMateDesktop-windows-x86_64.zip --report dist/acceptance-windows.json
```

Linux 将命令里的 `windows` 改成 `linux`，并在可截图、可使用剪贴板的桌面会话运行。

每个平台上传一个 artifact：原始 ZIP、`.zip.sha256` 和 `acceptance-<target>.json`。包内 `BUILD_INFO.json` 包含版本、提交 SHA、架构、公开/候选标记、工作区是否干净与文件哈希。

macOS 通过独立的 **Build macOS candidate (unverified)** 工作流（`macos-candidate.yml`）在主分支推送、标签推送或手动触发时，只构建按真实架构命名的 `MascotMateDesktop-macos-<arch>-candidate.zip`，不执行运行验收。它的失败不阻塞 Windows/Linux，候选包不进入正式 Release。

人工桌面复核建议覆盖：首次上手提示、透明背景边缘、菜单位置、抱起/落地、四方向偷看、F1/F3/F4、行为模式启动时回到安静模式，以及重启后大小和重力设置保留。遇到系统权限或确认弹窗时由用户正常批准，不绕过提示。

## 发布已经验收的同一批文件

除了标签构建自动发布，也可在 GitHub Actions 运行 **Publish accepted release**（`.github/workflows/promote-release.yml`），填写上述成功构建的 `candidate_run_id`。

工作流验证候选来自本仓库的 Package 工作流、执行成功，随后检出候选提交并下载其原始 artifact。`prepare_release.py` 校验两个平台的版本、提交、SHA-256、公开标记和成品验收报告；拒绝工作区不干净的构建、macOS/私用包、缺失验收、额外 ZIP 或哈希不匹配。

只发布这两个 ZIP，不重新构建：

- `MascotMateDesktop-windows-x86_64.zip`
- `MascotMateDesktop-linux-x86_64.zip`

附件同时提供 `SHA256SUMS.txt` 和两个验收报告。现有同名 tag 必须指向候选提交；现有 Release 不会被覆盖。发布说明包含下载/完整解压步骤、主分支改进、新数据目录、旧目录不会自动加载的变化及 macOS 待验证状态，并追加 GitHub 自动生成的 release notes。

## 公开内容与升级变化

公开目录仅复制 `license.redistributable` 严格为 `true` 的可安装皮肤及它们引用的 ZIP/预览；允许精选列表为空，保留外站浏览和手动导入。源码中的私用皮肤不删除。4 张偷看图片按当前约定原样保留并继续打包。

新数据根目录见 [状态与配置](configuration/state-and-config.md)。旧目录不自动读取或迁移，原文件保留。日聚合长期保留，原始事件仅保留最近 200 条；3/7/30 天采用包含今天的本地自然日。

不要提交 `dist/`、`build/`、`tools/`、Godot 缓存或个人数据。
