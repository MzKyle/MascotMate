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
