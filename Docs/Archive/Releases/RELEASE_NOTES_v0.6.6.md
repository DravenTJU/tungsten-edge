# Tungsten Edge v0.6.6

This release promotes the owner-verified stable rebuild as the new public version. It focuses on keeping taskbar cards stable across app lifecycle changes and making app-level behavior more predictable.

## What changed

- **Stable card placement after quit and relaunch**: kept and messaging apps now return directly to their remembered position without a first-frame slide from the tail.
- **Clearer stopped-app behavior**: stopped apps expose an **Open** command, and stopped messaging entries use the same dimmed appearance as other inactive launchers.
- **Consistent menus**: **Quit App** is always the final action in every chip menu.
- **Safer messaging-zone admission**: automatic registration now requires a recognizable main window, preventing apps with ambiguous windows from appearing twice or creating launcher entries that cannot reopen the intended window.
- **Reliable process liveness**: live apps are no longer treated as exited when LaunchServices temporarily loses them. This prevents an entire app's seats from being deleted and re-created as duplicate cards; process-exit cleanup now also emits one release record per seat.

## Stable rebuild note

The public `v0.6.6-beta.1` tested a broader Accessibility recovery path. That unverified experiment was not carried into this stable release; the regular v0.6.5 permission flow remains in place.

## Requirements

- macOS 12.0 Monterey or later
- Intel and Apple Silicon
- Accessibility permission is required to read and manage windows
- Finder content previews may additionally request Automation permission

## Install

1. Download `Tungsten-Edge-0.6.6.dmg`, open it, and drag **Tungsten Edge** into Applications. The ZIP contains the same app bundle.
2. This is an ad-hoc signed, unnotarized build. On macOS 14 and earlier, right-click the app and choose **Open**. On macOS 15 and later, try opening it once, then use **System Settings -> Privacy & Security -> Open Anyway**.
3. Grant **System Settings -> Privacy & Security -> Accessibility** when prompted.

## SHA-256

```text
10a53b8903f5b19238272f6ad154b449b962a224ba47db63aae51f7fda65c04e  Tungsten-Edge-0.6.6.dmg
3ebe3f6758ec8804e78503e5b441b3a071162b83f421b3727132a40eb1475bad  Tungsten-Edge-0.6.6.zip
```

---

# Tungsten Edge v0.6.6 中文说明

这一版将 owner 已实机验收的稳定重建线正式发布。重点是让应用启停、退出和窗口识别期间的任务条卡片保持稳定，同时统一应用级操作。

## 本次改进

- **退出、重开不再先滑到尾部**：保留应用和消息应用会直接回到记忆位置，不再出现首帧影子滑动。
- **未运行应用行为更清楚**：右键菜单增加「打开」；已退出消息应用与其他未运行启动器一样灰显。
- **菜单顺序统一**：「退出 App」始终是所有 chip 菜单的最后一项。
- **消息区准入更可靠**：自动注册必须先确认应用存在可识别的主窗口，避免窗口身份含糊的应用同时出现在消息区和实时窗口区，或生成无法正确唤醒主窗口的入口。
- **进程存活判断更可靠**：LaunchServices 瞬时丢失活进程时，不再误删整个应用及其全部座位，从源头避免同一窗口被重新准入成重复卡片；真实进程退出时也会为每个座位留下释放记录。

## 稳定重建说明

公开的 `v0.6.6-beta.1` 曾试验更宽的辅助功能权限恢复流程。该方案尚未完成稳定验收，因此正式版没有带入；当前继续使用 v0.6.5 的常规授权流程。

## 系统要求

- macOS 12.0 Monterey 及以上
- 支持 Intel 与 Apple 芯片
- 需要辅助功能权限来读取和管理窗口
- 访达内容预览可能额外请求自动化权限

## 安装

1. 下载 `Tungsten-Edge-0.6.6.dmg`，打开后把 **Tungsten Edge** 拖入「应用程序」；ZIP 内是同一个 App。
2. 本版本使用 ad-hoc 签名且未经过 Apple 公证。macOS 14 及更早版本请右键选择「打开」；macOS 15 及更新版本请先尝试打开一次，再到「系统设置 -> 隐私与安全性」选择「仍要打开」。
3. 按提示开启「系统设置 -> 隐私与安全性 -> 辅助功能」权限。
