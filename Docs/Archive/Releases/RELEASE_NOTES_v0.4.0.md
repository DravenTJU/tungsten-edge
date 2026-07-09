# Tungsten Edge 钨极 · v0.4.0

**Smoother switching, clearer status menu.** This release makes switching between apps look and feel far more stable — cross-app switches are now essentially flicker-free, something earlier releases explicitly called out as an accepted limitation. It also improves multi-display placement and adds more useful information to the status bar menu.

## What changed

- **Much smoother app switching** — switching between apps is now far more stable, with cross-app flicker essentially eliminated. Earlier releases (v0.3.0/v0.3.1) listed a residual flash as a known limitation; that's resolved in this release.
- **More reliable multi-display placement** — the taskbar, capsule, and drawer now stay correctly anchored to the physical screen edge, even when the native Dock appears/disappears or you switch between screens.
- **Richer status menu** — the wake-delay sliders now have inline explanations, the current app version is shown at the bottom of the menu, and a clear warning (with a direct link to System Settings) appears if Accessibility permission hasn't been granted yet.
- **Small polish** — refined wording on the wake slider menu, and fixed a display bug where the "stay visible / no wake" option could show a duplicated label.

## Requirements

- macOS 12.0 (Monterey) or later
- Intel and Apple Silicon (universal binary)
- Accessibility permission is required to read and manage windows.

## Install

### Homebrew

```bash
brew tap moonbai-studio/tungsten-edge
brew trust moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

### Direct download

1. Download `Tungsten-Edge-0.4.0.dmg`, open it, and drag **Tungsten Edge** into Applications, or unzip `Tungsten-Edge-0.4.0.zip` and move the app manually.
2. **First launch:** because this is still an unsigned / unnotarized early build, macOS may block it once. Right-click → Open on macOS 14 and earlier, or use System Settings → Privacy & Security → Open Anyway on macOS 15 and later.
3. Grant **System Settings → Privacy & Security → Accessibility**.

## Known limitations

- Not signed / notarized yet, so first launch still needs the macOS allow step.
- The UI is currently Chinese only.

---

# 中文

## 改了什么

这一版的重点是**让应用切换看起来更稳、状态栏菜单信息更全**。切换应用时的画面闪烁问题基本解决了——此前 v0.3.0/v0.3.1 的发布说明里还把它列为"暂时接受的限制"，这次是真的解决了。多屏使用时的贴边稳定性也有提升，状态栏菜单里的信息也更清楚。

- **应用切换更顺滑**：切换应用时的画面闪烁基本消失了，明显比之前的版本稳定。
- **多屏使用更稳**：不管是系统 Dock 出现/消失，还是在多个屏幕之间切换，任务条、胶囊按钮和抽屉都能稳稳贴在屏幕物理边缘，不会跟着跑位。
- **状态栏菜单信息更全**：唤醒延迟的滑杆旁边加了说明文字；菜单底部能看到当前的版本号；如果还没开辅助功能权限，会有醒目提示并能直接跳转到系统设置去开启。
- **小修小补**：唤醒滑杆菜单的文案更清楚了，也修了一个"常驻 / 不唤醒"选项偶尔显示重复文字的小问题。

## 系统要求

- macOS 12.0 (Monterey) 及以上
- Intel 与 Apple 芯片均可（通用二进制）
- 需要辅助功能权限来读取和管理窗口。

## 安装

### Homebrew

```bash
brew tap moonbai-studio/tungsten-edge
brew trust moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

### 直接下载

1. 下载 `Tungsten-Edge-0.4.0.dmg`，打开后把 **Tungsten Edge** 拖进「应用程序」，或解压 `Tungsten-Edge-0.4.0.zip` 后手动移动 app。
2. **首次打开**：因为这仍然是未签名 / 未公证的早期版本，macOS 可能会拦截一次。macOS 14 及更早版本请右键 → 打开；macOS 15 及更新版本请到「系统设置 → 隐私与安全性」里点「仍要打开」。
3. 在「系统设置 → 隐私与安全性 → 辅助功能」里给 Tungsten Edge 打开权限。

## 已知限制

- 还没有签名 / 公证，首次打开仍需要 macOS 放行步骤。
- 界面目前仍是中文。
