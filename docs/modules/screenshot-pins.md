# 截图贴图

截图贴图模块提供类似 PixPin 的轻量工作流：区域截图、保存最近历史、轮换贴图、关闭当前贴图。

## 默认快捷键

| 快捷键 | 命令 | 说明 |
| --- | --- | --- |
| `F1` | screenshot | 区域截图，保存到历史，并尽量复制到剪贴板 |
| `F3` | paste_pin | 按最新、上一次、上上次顺序贴出截图 |
| `F4` | close_pin | 关闭当前贴图 |

右键菜单中的“截图贴图设置”可以修改快捷键和最大贴图数。

## 配置文件

配置保存在：

```text
~/.config/mascotmate-desktop/config.json
```

默认结构：

```json
{
  "shortcuts": {
    "screenshot": "F1",
    "paste_pin": "F3",
    "close_pin": "F4"
  },
  "screenshot": {
    "backend": "auto"
  },
  "pins": {
    "max_count": 3
  }
}
```

`max_count` 会被限制在 1-3 之间。

## 截图后端

| 后端 | 命令 | 能力 |
| --- | --- | --- |
| `auto` | Godot `DisplayServer` | 捕获鼠标所在屏幕，弹出区域选择窗口，保存 PNG |
| 兜底 | KDE Spectacle / ImageMagick `import` | Linux 上 Godot 截图不可用时自动尝试 |

截图前，主窗口和已有贴图窗口会短暂隐藏，避免截到桌宠本身。旧配置里的 `spectacle` / `import` 偏好会在启动时重置为 `auto`。

## 图片剪贴板

截图保存后会调用 `scripts/pet_helper.py copy-image <png>` 或打包后的 `scripts/pet_helper copy-image <png>` 复制图片：

- Windows：PowerShell / .NET `System.Windows.Forms.Clipboard`
- macOS：`osascript`
- Linux：优先 `wl-copy --type image/png`，再尝试 `xclip -selection clipboard -target image/png`

如果图片剪贴板复制失败，截图仍会保存到历史，并可用 `F3` 贴图。

## 全局快捷键桥接

Godot 本身只能稳定处理应用聚焦时的输入。全局快捷键由跨平台 helper 完成：

1. `ScreenshotPins.gd` 启动 `pet_helper hotkeys`
2. Linux/X11 使用 `XGrabKey`，Windows/macOS 使用 `pynput`
3. 用户按快捷键时，helper 向 `127.0.0.1:38291` 发送 UDP 命令
4. `ScreenshotPins.gd` 轮询 UDP 并执行截图、贴图或关闭

如果端口不可用、helper 缺失、权限不足或 Wayland 会话不允许全局热键，模块会保留应用内快捷键作为兜底。

## 贴图窗口

每张贴图是一个独立的 Godot `Window`：

- 无边框
- 置顶
- 透明
- 不可缩放
- 只显示图片内容
- 左键拖动
- 拖动时自动限制在屏幕范围内

点击或拖动过的贴图会成为 `active_pin`。`F4` 优先关闭当前贴图，如果没有当前贴图则关闭最后创建的贴图。

## 平台限制

Wayland 合成器通常不允许普通应用随意注册全局快捷键或操控其他窗口层级；macOS 也会限制未经授权的全局快捷键监听。因此：

- Wayland 下默认不启用全局快捷键辅助脚本
- 应用窗口聚焦时仍可使用快捷键
- macOS 首次启用全局快捷键时，可能需要给 helper 授予辅助功能权限
- Linux 图片剪贴板复制依赖 `wl-copy` 或 `xclip`
