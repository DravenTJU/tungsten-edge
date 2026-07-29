# UserDefaults 数据边界（从回滚账本搬出）

2026-07-30 从 `Docs/23-rollback-ledger.md` 移出。这两节记的是**两次具体改动**的 UserDefaults 键迁移细节：代码可以 `git revert`，但用户磁盘上的数据不会跟着回退，所以要单独说明回滚后旧版会读到什么。

搬出的理由：它们是一次性的迁移考据，早已稳定；留在账本里会挤占「回退命令速查」这个主用途。回退命令本身仍在账本，这里只补数据侧的注意事项。

**键的当前权威定义在 `AGENTS.md` 的 Kept Apps 一节**（哪些键可写、哪些冻结只读、迁移按什么判定）。本文只记两次迁移当时的实测状态。

---

## 抽屉位置与退出后保留拆分（`5f5efa0`）

- 代码回滚命令为 `git revert 5f5efa0`；这不会自动回滚 `UserDefaults` 数据。
- 抽屉键由新旧两个版本共享；新版本新增的 `keptAppBundleIDsV2` 被旧版本忽略。旧 `keptAppBundleIDs` 保持升级前内容，不由迁移覆写。
- 回滚并启动旧版后，旧版会按升级前的旧保留名单继续执行原有"kept 胜出"启动修复，可能把与旧保留名单重叠的部分应用踢出抽屉。这个局部抽屉位置变化是已接受的回滚结果。

## 消息应用纳入统一保留勾选（`a25add5`）

- 代码回滚命令 `git revert a25add5`；不自动回滚 `UserDefaults`。
- 三组键各升一版、旧键冻结只读：新增 `keptAppBundleIDsV3` / `messagingBundleIDsV2` / `messagingOptOutBundleIDsV2`；冻结 `keptAppBundleIDsV2`、`keptAppBundleIDs`、`pinnedAppBundleIDs`、`messagingBundleIDs`、`messagingOptOutBundleIDs`（新版一律不删不覆写）。
- 迁移把现有 kept 名单 + 消息名单并入 V3（消息应用默认勾保留，升级观感不变）。实测：升级后 `keptAppBundleIDsV3` = 原 24 个 kept + 微信 / QQ / 飞书，`keptAppBundleIDsV2` 冻结不变。
- 回滚到 `a25add5` 之前的版本：旧版只读冻结旧键（升级前快照），新版对消息应用的 kept / 标记 / 取消一律不带回；旧版启动修复遍历的是 kept V2（不含本次迁入的消息 kept，那些只在 V3），因此**不会误取消消息标记**。回滚干净。
- `drawerBundleIDs` 仍两版共享：新版用户主动拖动改的位置会被旧版读到，属既有位置数据、不宣称回滚。
