# Tungsten Edge v0.5.0

This release expands Tungsten Edge from a per-window taskbar into a more complete macOS work shelf, with stronger window identity and native-tab handling for everyday use.

## What changed

- **Kept apps and a clearer drawer**: "Keep in Dock" preserves an app at its current taskbar position when it exits or has no real window. The drawer separates running and not-running apps and uses the same membership model.
- **Reversible drag workflows**: window cards, kept apps, drawer apps, and messaging apps can move between their supported zones without losing order; cancelled drags roll back cleanly.
- **Pinned folders and Shelf**: pin project folders for quick browsing, move dropped files into a pinned folder without overwriting existing files, and keep temporary file references in Shelf without moving the originals.
- **Finder content previews**: preview the contents of a concrete Finder folder window when it can be matched reliably.
- **Persistent messaging entries**: messaging apps stay available when not running, can be reordered in their own zone, and can move between that zone and the drawer.
- **Window reliability and polish**: improved action targeting, running indicators, menu wording, popup rendering, multi-display placement, and native-tab folding, including recovery from minimized tab groups that split after a dock restart.
- **Clearer permission setup**: the app now presents a dedicated Accessibility permission guide, with Automation permission requested only when Finder content previews need it.

## Requirements

- macOS 12.0 (Monterey) or later
- Intel and Apple Silicon (universal binary)
- Accessibility permission is required to read and manage windows.
- Finder content previews may additionally request Automation permission.

## Install

1. Download `Tungsten-Edge-0.5.0.dmg`, open it, and drag **Tungsten Edge** into Applications, or unzip `Tungsten-Edge-0.5.0.zip` and move the app manually.
2. This is an ad-hoc signed, unnotarized early build. On macOS 14 and earlier, right-click the app and choose **Open**. On macOS 15 and later, try opening it once, then use **System Settings -> Privacy & Security -> Open Anyway**.
3. Grant **System Settings -> Privacy & Security -> Accessibility**.

## Known limitations

- The build is not Apple-notarized, so macOS requires the one-time allow step above.
- The interface is currently Chinese only.

---

# 中文

这一版把 Tungsten Edge 从“一窗一卡”的窗口任务条继续扩展成更完整的 macOS 底部工作台，同时加强日常使用中的窗口身份与原生标签处理。

## 主要变化

- **固定应用与更清楚的抽屉**：选择“在程序坞中保留”后，应用退出或暂时没有真实窗口时，会在原位置保留应用入口。抽屉按运行 / 未运行分区，并与固定应用使用统一的成员关系。
- **可撤销的跨区拖拽**：窗口卡片、固定应用、抽屉应用和消息应用可在各自支持的区域间移动；取消拖动时会完整恢复，不丢顺序。
- **固定文件夹与 Shelf 中转格**：常用项目文件夹可以固定到底部；文件可直接拖入固定文件夹且不会覆盖同名内容；Shelf 只保存临时文件引用，不移动原文件。
- **Finder 内容预览**：当具体 Finder 文件夹窗口可以被可靠匹配时，可直接预览其中内容。
- **消息应用常驻入口**：消息应用未运行时仍保留灰色入口，可在消息区重排，也可与抽屉双向拖动。
- **窗口可靠性与细节打磨**：加强动作目标、运行状态、菜单文案、弹窗渲染、多屏定位和原生标签折叠，并修复 Dock 重启后最小化多标签窗口可能裂成多张卡片的问题。
- **更清楚的权限引导**：新增独立的辅助功能权限引导；只有 Finder 内容预览需要时才会请求自动化权限。

## 系统要求

- macOS 12.0 (Monterey) 及以上
- Intel 与 Apple 芯片均可（通用二进制）
- 需要辅助功能权限来读取和管理窗口
- Finder 内容预览可能额外请求自动化权限

## 安装

1. 下载 `Tungsten-Edge-0.5.0.dmg`，打开后把 **Tungsten Edge** 拖进“应用程序”；也可以下载 `.zip` 解压后手动移动。
2. 这是 ad-hoc 签名、尚未公证的早期版本。macOS 14 及更早版本请右键应用并选择“打开”；macOS 15 及更新版本请先尝试打开一次，再到“系统设置 -> 隐私与安全性”中选择“仍要打开”。
3. 在“系统设置 -> 隐私与安全性 -> 辅助功能”中为 Tungsten Edge 开启权限。

## 已知限制

- 还没有完成 Apple 公证，首次打开需要按上面的步骤手动放行一次。
- 界面目前仍以中文为主。
