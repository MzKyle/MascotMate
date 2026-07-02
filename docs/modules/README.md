# 模块总览

这个项目的模块划分比较直接：Godot 脚本负责桌宠运行时，Python/Bash 脚本负责离线生成、启动和打包。

## 阅读顺序

建议按下面顺序理解：

1. [窗口与物理](modules/window-and-physics.md)：理解为什么窗口位置就是桌宠的世界坐标。
2. [交互控制](modules/interaction.md)：理解点击、长按、拖拽、甩飞如何识别。
3. [行为系统](modules/behavior.md)：理解安静、活泼、捣乱三种模式。
4. [截图贴图](modules/screenshot-pins.md)：理解跨平台快捷键、截图后端和贴图窗口。
5. [素材与动作](modules/assets.md)：理解资源目录和 `actions.json`。
6. [打包模块](modules/packaging.md)：理解 portable bundle 与 Godot export。

第三方皮肤作者应优先阅读 [皮肤包规范](../sdk/skin-package-spec.md) 和 [Shimeji-ee 导入](../sdk/shimeji-import.md)。

## 运行时原则

- 每帧只做必要的窗口位置、动画帧和物理更新。
- 角色可见区域由透明 PNG 的 used rect 估算，减少不可见区域占用鼠标事件。
- 右键菜单是主要功能入口，避免在桌面上常驻复杂 UI。
- 角色状态轻量持久化，行为模式每次启动重置到安静模式。
- 截图贴图把系统差异集中在 `ScreenshotPins.gd` 和 `pet_helper.py`。
