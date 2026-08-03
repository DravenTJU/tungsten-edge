# 29 · 发版 Runbook（照着做就能发）

> **读者是没见过这个仓库的 agent（或隔了很久回来的自己）。** 照顺序执行，别自己发明流程。
> 内容全部来自实操验证过的 v0.7.0 → v0.7.4 五次发版；每条 ⚠️ 后面都是真踩过的坑，不是假设。
>
> **这是本项目唯一公开不可逆的动作。** GitHub release 和 Homebrew cask 直接面向真实用户：
> cask 里的 sha256 写错，所有人 `brew install` 直接坏掉，且要等用户报错才会知道。
> 每一步的校验都不要跳。
>
> 本文档 2026-08-03 建立（v0.7.4 发版时逐步记录）。在此之前流程只存在于某个 agent 的
> 私有记忆里，别的 agent 读不到——这是把它落进仓库的原因。

## 发版前两道闸

**① owner 实机验收所有「待验收」项。** 看板 `进度看板.html` 主线里标着「待实机验收」的、
以及 `Docs/23-rollback-ledger.md` 表里写着「owner 实机验收待完成」的，发版前必须清零。
**把待验步骤写成清单交给 owner，不要自己用 AX / System Events 硬自动化**——
理由见 `Docs/28-process-pitfalls.md`《验收方式》。

**② 账本全表复检**（`Docs/23-rollback-ledger.md`）。逐条实跑：

```bash
for c in <表里每个提交号>; do
  git merge-tree --merge-base=$c HEAD ${c}^ >/dev/null 2>&1
  printf "%s %s\n" "$c" "$([ $? -eq 0 ] && echo ✅ || echo ⚠️)"
done
```

⚠️ **别用 `git apply --check --reverse` 代替**：它要求上下文严格对齐，而 `git revert` 走三方合并，
前者给出大量假阳性（2026-07-29 首次复检被误导过一次）。二进制文件在它下面必然假阳性。
复检结果写回账本顶部，并注明日期与条目数。

## 一、版本号（问 owner，别自己定）

行为变更走 minor、纯修复走 patch——但这不是硬规矩（v0.7.1 和 v0.7.4 都带着行为反转却走了
patch），**最终由 owner 拍板**。

`macos-dock-cc-v2.xcodeproj/project.pbxproj` 里两个键**各 4 处**，一起改：

```bash
sed -i '' 's/CURRENT_PROJECT_VERSION = <旧>;/CURRENT_PROJECT_VERSION = <新>;/g; \
           s/MARKETING_VERSION = <旧版本>;/MARKETING_VERSION = <新版本>;/g' \
  macos-dock-cc-v2.xcodeproj/project.pbxproj
```

改完 `grep -c` 确认新值各 4 处、旧值 0 处。build 号单调递增（0.7.2→14 / 0.7.3→15 / 0.7.4→16）。

## 二、发布提交与标签

发布提交**直接打在 `master`**（不是临时分支），标题「发布：准备 Tungsten Edge vX.Y.Z」，
只带版本号改动。

```bash
git tag -a vX.Y.Z -m "Tungsten Edge vX.Y.Z"   # ⚠️ 必须附注标签
git push origin master
git push origin vX.Y.Z                         # ⚠️ 必须单独推
```

⚠️ **轻量标签 `git push --follow-tags` 带不走**——v0.7.0 因此静默漏推，事后才补。
`v0.6.5` / `v0.7.0` 那两个历史轻量标签**不追改**（会改写公开标签）。

## 三、打包

```bash
./Scripts/package_release.sh     # 约 2–3 分钟
```

产物在 `dist/`：`.dmg`（拖拽安装）+ `.zip`（Homebrew 用），脚本结尾会打印两个 sha256。
脚本内部：clean build 通用 Release（x86_64 + arm64）→ **把 LICENSE 塞进 bundle 和 DMG 根**
→ ad-hoc 签名。

⚠️ **LICENSE 必须在 `codesign` 之前**放进 bundle（GPL 送达要求；往已签名的 bundle 里加文件
会破坏签名）。重写这个脚本时不要丢掉——`AGENTS.md` 里也有同一条约束。

目前是 **ad-hoc 签名、未公证**，所以发布说明里必须带「右键→打开」的放行说明。
（完整的 Developer ID + 公证流水线封存在废弃开发线 `codex/release-v0.6.6` 上，见账本。）

## 四、发布说明

**写中文**（旧记忆一度错记成英文，实际 v0.6.6 起全是中文）。结构照
`Docs/Archive/Releases/RELEASE_NOTES_*.md`：一句总述 → 分节讲每块 → 安装（DMG / Homebrew /
未签名放行 / 辅助功能权限）。**同时归档一份到 `Docs/Archive/Releases/`**。

⚠️ **对用户可见的行为反转永远放最前面，并明说"升级后会怎样"和"怎么恢复"。**
v0.7.1 撤销「彻底隐藏」时立的规矩，v0.7.4 避让改默认关时照办。
**版本号是 patch 时更要守**——patch 号不会向用户暗示有行为变更，用户只能从说明里知道。

写完**先让 owner 扫一眼再发**。然后：

```bash
gh release create vX.Y.Z dist/*.dmg dist/*.zip \
  --title "Tungsten Edge vX.Y.Z" \
  --notes-file Docs/Archive/Releases/RELEASE_NOTES_vX.Y.Z.md
```

（gh 账号 `gmhw11-netizen`，已登录、https 可推。）

## 五、Homebrew cask

本地 tap 在 `~/Projects/homebrew-tungsten-edge`。

⚠️ **先 `git checkout master && git pull`**——这个检出常年停在旧分支，直接改会改错地方。

改 `Casks/tungsten-edge.rb` 两行：`version` 和 `sha256`。
⚠️ **sha256 用 zip 的那个，不是 dmg 的**（cask 的 url 指向 zip）。
url 靠 `#{version}` 插值自动跟随，不用动。

**推之前先做端到端校验**（比事后校验安全：不一致的哈希根本不会到达用户）：

```bash
curl -sL -o /tmp/verify.zip "https://github.com/moonbai-studio/tungsten-edge/releases/download/vX.Y.Z/Tungsten-Edge-X.Y.Z.zip"
shasum -a 256 /tmp/verify.zip     # 必须 == cask 里写的 == 本地 dist/ 里的
```

三者一致再 `git commit -m "tungsten-edge X.Y.Z" && git push origin master`。
最后 `brew update && brew info --cask moonbai-studio/tungsten-edge/tungsten-edge` 确认版本号。

## 六、收尾登记

1. **账本 `Docs/23-rollback-ledger.md`**：新增一段——发布提交号、DMG/ZIP 双哈希、
   cask 同步点（tap 仓库的提交号）、本版是否含用户可见的行为反转。
2. **看板 `进度看板.html`**（owner 的 Obsidian 库，**不在 git 里**）：
   ⚠️ 改之前先复制一份到 `Archive/看板快照/进度看板-YYYY-MM-DD-<做了什么>前.html`——这是唯一的后悔药。
   只改文件内 `<script id="board-data">` 的 JSON，**不碰布局代码**。
   主线加发布条目、`meta.version` / `commit` / `build` / `updated` / `here` 更新、
   销掉本版已经兑现的待办卡。
3. `AGENTS.md` 的 Source Of Truth 若有相关指针，一并更新。

## 长期坑（每次都会咬一口）

- **发布后 `master` 不再 bump 版本号**，于是开发构建与已发布包版本号完全相同。
  用户报「菜单里没有某项」时**先比对提交，别信版本号**——v0.6.6 那次实为发布落后开发线 14 小时。
  `BuildProvenance` 的版本行后缀（Debug / 安装位置）是肉眼区分两者的唯一手段。
- **只能有一份 `/Applications/Tungsten Edge.app`**。留个 `*-backup` 在旁边会让
  LaunchServices 的 bundle-id 解析变得不确定。
- 开发构建与已安装版**共用一个 bundle id、因此共用一份辅助功能授权**，别让两边同时授权。
