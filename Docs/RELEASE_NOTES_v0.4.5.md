# Tungsten Edge v0.4.5

This release publishes the three post-v0.4.0 stability fixes from `master @ 2fac13a`.

## What changed

- Fixed a Finder restore edge case where the taskbar could briefly disappear because a restored Finder window was misclassified as fullscreen.
- Fixed minimized-window restore so it no longer brings a sibling window from the same app above the previous foreground app.
- Fixed a stale optimistic frontmost state issue that could make a visible background-window chip minimize instead of activate.

## 中文

这一版只发布 `v0.4.0` 之后已经提交到 `master @ 2fac13a` 的三项稳定性修复：

- 修复 Finder 窗口恢复后，任务条因全屏误判而短暂消失的问题。
- 修复最小化窗口恢复时，同一个 app 的兄弟窗口被顺带带到前面的情况。
- 修复后台可见窗口卡片偶发把“激活”误判成“最小化”的问题。
