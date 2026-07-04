# 开发流程

## 修改动作素材

1. 把动作帧放入 `resource_hd/<动作目录>/`
2. 需要从外部源生成高清副本时运行：

```bash
python3 scripts/generate_hd_assets.py --source /path/to/source --output resource_hd --scale 3 --force
```

3. 修改 `scripts/generate_godot_manifest.py` 中的动作定义
4. 重新生成清单：

```bash
python3 scripts/generate_godot_manifest.py
```

5. 启动桌宠确认动作：

```bash
scripts/run_godot_pet.sh
```

## 修改交互或物理

建议先用安全窗口模式验证逻辑：

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

确认逻辑正确后，再打开透明窗口检查鼠标穿透：

```bash
scripts/run_godot_pet.sh
```

重点测试：

- 单击、双击、右键、滚轮
- 长按抱起
- 慢速释放
- 快速甩飞
- 撞墙和落地
- 拖到边缘进入偷看
- 右键菜单项是否仍能点击

## 修改气泡文案或陪伴行为

文案入口：

- 本地候选：`godot_pet/scripts/CompanionExpressionBank.gd`
- intent fallback：`godot_pet/scripts/CompanionExpressionResolver.gd`
- 手动路径 fallback：`godot_pet/scripts/Main.gd`
- 自动 prompt 默认 message：`BehaviorBrain.gd` 和 `CompanionBehaviorPolicy.gd`
- 可选 AI stub fallback：`scripts/companion_ai_sidecar.py`

如果新增或改名表达 key，要同步：

```bash
python3 scripts/run_godot_smoke.py
python3 -m unittest discover tests
```

如果新增文案语气，要同步 `ConfigStore.gd`、`PetMenuController.gd`、`Main.gd`、`scripts/skin_store_server.py`、`companion_console/` 和配置文档。

## 修改应用图标

需要同时更新：

```text
godot_pet/assets/app_icon.png
packaging/icons/mascotmate-desktop.png
```

然后确认：

```bash
python3 scripts/run_godot_smoke.py
scripts/build_godot_linux.sh
scripts/install_desktop_entry.sh
```

`install_desktop_entry.sh` 使用 `packaging/icons/mascotmate-desktop.png`，不再从动画帧中抽图。

## 修改截图贴图

建议在目标桌面系统下测试；Linux 可以先确认当前会话：

```bash
echo "$XDG_SESSION_TYPE"
scripts/run_godot_pet.sh
```

检查：

- `F1` 是否触发截图
- 截图时主窗口和贴图窗口是否隐藏
- 区域选择、保存历史和图片剪贴板是否生效
- `F3` 是否按最近历史轮换贴图
- `F4` 是否关闭当前贴图
- 设置窗口保存后全局快捷键是否重启
- `~/.config/mascotmate-desktop/config.json` 是否正确写入

## 文档本地预览

```bash
cd docs
python3 -m http.server 4173 --bind 127.0.0.1
```

访问：

```text
http://127.0.0.1:4173/
```

新增文档后记得同步 `_sidebar.md`。
