# AGENTS

> **New agent: read this first.**
> Live product state, roadmap, and rationale live in the owner's Obsidian vault, not here:
> `/Users/caye/Documents/Obsidian Vault/Projects/macos-dock-cc-v2/` — entry note `00 macos-dock-cc-v2 总览.md`.
>
> `AGENTS.md` is only for engineering **do-not-revisit guardrails**: placement, taskbar trust, window/card identity, focus/action semantics, drag mechanics, panel geometry, and compatibility traps. Product wording, roadmap, UX rationale, and reversal logs stay in Obsidian. Dated `Docs/*` are historical records except `Docs/05-known-platform-quirks.md`, which is kept as a repo-local platform reference.

## Purpose

This repo is v2 of a macOS window-oriented bottom taskbar. The foundation-engine phase is done; current work is UX/behavior refinement. Do not rebuild the Finder foundation or return to bottom-up discovery of every CG/AX window-like surface. The mainline is inventory-first taskbar trust.

## Source Of Truth

- Product state / roadmap / decision rationale: Obsidian entry `00 macos-dock-cc-v2 总览.md`.
- Engineering hard constraints: this file.
- Platform quirks: `Docs/05-known-platform-quirks.md`.
- Focus / activation debug history: `Docs/22-window-focus-flicker-debugging.md`.
- Finder P0 implementation / samples: `Docs/17-finder-p0-implementation.md`, `Docs/18-real-sample-finder-findings.md`.

## Placement And Trust

### Slot Placement

- Minimize does **not** release a slot.
- Hide does **not** release a slot.
- Temporary CG disappearance does **not** release a slot.
- Only true close releases a slot.
- Do not reintroduce held-slot TTL or "expire then return to tail" as the default placement rule.

### Taskbar Trust

- Only trusted, user-operable windows enter the bottom strip. Filter system internals, widgets, app extensions, transparent/fake surfaces before any keep-slot or disappeared retention.
- The trust model starts from app-level window inventory: `WorkspaceSource` enumerates normal user apps through `NSWorkspace`, reads `AXWindows`, and emits `.appWindowInventory`.
- Inventory reads use a 100ms per-app AX timeout, up to 12 concurrent app reads, and 30-round unread degradation before CG can help decide whether windows still exist.
- While inventory-first is available, CG and generic `.accessibility` observations must not create ordinary new strip entries; they may prove/enrich inventory entries. Reduced-permission mode may create CG fallback entries.
- Debug rollback flags: `DOCK_INVENTORY_FIRST_ENABLED=0`, `DOCK_AX_ADMISSION_MODE=legacy`.
- Do not widen AX sampling again without strict window-type filtering and an observation-count guardrail. Full incident/history: `Docs/19-taskbar-trust-incident.md`, `Docs/20-inventory-first-taskbar-trust.md`.

### Long-Gap Duplicate Cards

- Before creating a new identity, match conservatively against current `DockSnapshot` seats for same process and same app.
- Prefer title + nearby frame; ambiguous candidates do not merge.
- Never revive `app-*` ids or `closedPending` records.
- Details: `Docs/21-long-gap-duplicate-card-fix.md`.

## App-Specific Rules

### Finder

- Finder always has a persistent taskbar slot. `seedRunningApps` adds Finder unconditionally, so the chip survives when all Finder windows are closed.
- Closed-window Finder appears as `app-com.apple.finder`; clicking it opens the home directory, matching system Dock behavior.
- Never plan `hideApp` / minimize for the Finder persistent `app-*` chip. Always activate/open, even if Finder is frontmost after its last window closes.
- Do not let process-death reconcile remove Finder's app entry. `handleAppTerminated` clears windows but keeps the slot; reconcile must skip Finder when sweeping dead pids.
- Finder process existence alone does **not** mean there is a Finder window.
- Concrete Finder folder windows remain window-level items when title/frame are available.
- If a specific Finder window target cannot be captured, do **not** fall back to whole-app activation; that can bring the wrong Finder window(s) forward.
- Finder minimize feedback accepts either `minimized` or temporary `disappeared`, because macOS can report concrete minimized Finder windows either way.

### Feishu

- Feishu window-level handling is opportunistic.
- If frontmost AX windows are unreliable, titles are generic/missing, or AX samples are weak, fall back to one stable app-level item.
- Do not block the taskbar mainline on perfect Feishu per-window fidelity. A stable app-level Feishu fallback is sufficient for current validation.

## Window And Card Identity

### Native Tabs — single-seat model

- Model: **one physical window = one seat = one chip**. Background native tabs are not separate seats.
- Seat token is stable (`tabgrp-<pid>-s<serial>`) from a monotonic counter. Never derive the stable token from `cgWindowID`; active tab cgIDs are reused and swap.
- `WindowRecord.id` may be `cgw-<activeCgID>`, but the chip's stable identity is `groupID = seat.token`; action target is the current active cgID.
- Tab switch: if the active cgID leaves AX and a new cgID appears at the same frame, adopt it into the same seat only when exactly one seat claims that frame.
- Tear-out: if the old active cgID moves to a new frame while another tab takes the old frame, the old-frame seat adopts the new active tab and the moved cgID becomes a fresh seat.
- Minimized multi-tab windows: Ghostty can expose all tabs as eligible AX windows with `min=true`. Fold background tabs into the already-placed seat; do not create one chip per tab. Fold by exact frame first, then by `min=true` + off-screen + same width/height as the placed minimized seat. Do **not** revert to exact-frame-only.
- Seat removal: minimized or hidden seats stay; normal AX-absent-but-CG-present windows get only a short close grace; if cgID is gone from full CG list, drop immediately.
- Superseded: do not revive "reap any AX-absent-but-CG-present seat after grace" or "keep every tab as a seat then collapse by token".

### Strip Action Target

- A strip chip id is a stable identity token, not necessarily an actionable window id.
- All strip show/hide/minimize/toggle calls must use `item.actionWindowID`.
- Drawer actions are app-centric and must not use strip chip ids for window-level toggle.

## Action Planning And Focus

### Minimize Returns Focus To Previous App

- Minimizing the frontmost focused window A1 of multi-window app A should return focus to the previous **other** app B, not A's sibling A2.
- Mechanism: before minimizing, `findBackgroundActivationTarget(for:)` picks B, then `switchFrontmostWithoutReorder(toPID:)` uses `SetFrontProcessWithOptions(.frontWindowOnly)`.
- Guard: only fire when the handle is the frontmost app's focused AX window; right-click-minimizing a non-focused sibling must not steal focus. Candidate B must be `.regular` and pass `DockWindowEligibilityPolicy`.
- If the symbol is missing or switch fails, fall back to the old post-activate path for that call.
- Do not chase zero-flicker again. Probes showed suppressing A2's promotion requires bringing B front.

### Activation / Restore Focus

- `postSkyLightWindowFocus` is the shared core: `_SLPSSetFrontProcessWithOptions(psn, wid, kCPSUserGenerated)` plus two make-key events. Byte layout is load-bearing: `[0x04]=0xf8`, `[0x08]=0x0d`, first `[0x8a]=0x02`, second `[0x8a]=0x01`, wid at `0x3c`, no `0xff` fill.
- Early focus applies only to `.activateWindow`, cross-app, visible active/inactive windows, using snapshot `record.cgWindowID`. It must happen before handle capture and must not resolve wid via AX or on-screen CG.
- Minimized restore = **restore-then-switch**, never switch-early. While target B1 is order-out, any front-process switch can promote visible sibling B2 above old front app A1. Exclude `.minimized` from `focusWindowEarly`; after `setMinimized(false)`, immediately call `postSkyLightWindowFocus` with snapshot wid (`knownCGWindowID`) and zero AX in between.
- Minimized restore must set `kAXMainAttribute=true` after restore+switch. Make-key while a window is order-out can land on a visible sibling; keep the correction.
- Action-decision paths must not use `NSWorkspace.frontmostApplication`; it is a lagging notification cache after SkyLight switches. Use fresh `NSRunningApplication(processIdentifier:)?.isActive`.
- Kill switch: `DOCK_SKYLIGHT_FOCUS=0` disables early and post-capture SkyLight focus. SkyLight private return codes are diagnostics only; do not re-add nonzero-return fallback gating.
- Full debug record: `Docs/22-window-focus-flicker-debugging.md`.

### Optimistic Action State

- Clicking a chip writes an `OptimisticWindowState` for predicted **status only**, cleared when snapshot confirms or after ~4s. No spinner.
- Do not re-add predicted `isAppFrontmost`. The frontmost axis is always a fresh `NSRunningApplication(pid).isActive` read, injectable in `LifecycleActionPlanner.init` for tests.
- The old `isAppFrontmost=true` could linger for 4s and turn a background-window click into minimize. Accepted micro-edge: a click within the few ms before activation lands may repeat activate; that is harmless.
- Scope is show/hide only: toggle / activate / minimize / hide. Close / quit stay locked until confirmed.
- The chip tap pulse (`ChipView.isTapPressed`, brief 0.93 press-and-spring) is a **view-local acknowledgment only** — it exists because activating an already-visible window changes nothing on the bright/dim axis. It must stay declarative (`.animation(value:)`, per the LauncherChip zombie-animation lesson) and must never feed the planner or any frontmost decision. A persistent "frontmost highlight" axis (Option 2, 2026-07-06) is deliberately NOT built; it brushes against the no-predicted-frontmost fence — needs an owner decision first.

## Drag, Drawer, And Ordering

### No System Drag Image (scope: chip drags only)

- Do not reintroduce SwiftUI `.onDrag` / `NSItemProvider` or AppKit `beginDraggingSession` for **strip/drawer/folder chip drags**. System-owned drag images cause an unsuppressible release ghost on chip visuals.
- The carried image is self-drawn and owned by `DragController` for cross-panel drags.
- **Exempt: real file drag-and-drop (2026-07-06).** Popup/shelf grid cells use `.onDrag { NSItemProvider(contentsOf:) }` to drag files OUT to other apps — a system drag is the only way to deliver a pasteboard payload cross-app, and the system drag image is the desired native look there. Likewise SwiftUI `.onDrop` destinations for files dragged IN are fine; they never enter DragController's NSEvent-monitor pipeline, so the two systems cannot conflict.

### External File Drop-In (Finder → strip)

- The strip's `.onDrop` must stay attached at the **same view level that declares the `"strip"` coordinate space** — never after `.padding(shadowPadding)` — so `DropInfo.location` is same-source with `folderChipFrames`/`shelfFrame`.
- Routing geometry is the pure function `StripDropRouting.route` (shelf hit → stash; folder-zone x-range + 24pt tail slack → pin at index; else reject). Keep it pure and unit-tested; do not inline geometry into the DropDelegate.
- The shelf chip's frame lives in its own `ShelfFramePreferenceKey`/`shelfFrame`. Do **not** put a sentinel key into `folderChipFrames` — that dict is folder-chips-only and feeds folder reorder hit-tests.
- Only directories can pin; files dropped on the folder zone are a silent no-op (directory-ness is unknowable synchronously during hover — accepted micro-edge). Re-dropping an already-pinned folder repositions it (`PinnedFolderStore.insert` move semantics).

### Shelf (中转格)

- The shelf holds **references only** (bare paths, newest first). Never move/copy files implicitly; the receiving app decides on drag-out. `ShelfStore.prune()` runs on every shelf-popup open to drop dead paths. No bookmarks in v1.
- The shelf chip is a fixed head of the pinned-folder zone (`StripEntry.shelf`), click + drop target only — never draggable, never a `DragController` source.
- Shelf popup reuses the single shared popup panel via `PanelCoordinator.PopupContent` (`.folder(path)` / `.shelf`); the one-popup-at-a-time invariant must survive any refactor. Shelf grid: no drill-in, no Finder tail cell, tap = open.

### Strip Drag-Reorder

- Strip in-panel reorder uses one `"strip"` coordinate space for chip frames, finger location, and floating copy.
- Chip frames are read via `.background` GeometryReader, not `.overlay`, because overlay can steal clicks.
- Keep `grabOffset` so edge-grabs do not snap the copy center to the cursor.
- Keep mouse-up fallback and live-order disappearance cleanup so canceled gestures or vanished windows do not leave gaps.
- Floating copy forces hovered visual (`ChipView.forceHover`) and disables hit testing.

### Cross-Panel Drag Controller

- `DragController` is the single authority for local/global monitors, carrier `NSPanel`, source/destination conversion, drop decisions, and idempotent teardown.
- Carrier panel is screen-spanning, transparent, click-through, level `.popUpMenu`, and ordered out on every teardown path.
- Use `NSEvent.mouseLocation` screen coordinates for carrier position and cross-panel hit testing; do not use strip/drawer local coordinates for those decisions.
- Reorder while dragging is driven by `dragController.globalLocation`, not per-chip `DragGesture.onChanged`. SwiftUI cancels a chip gesture once the grid moves the dragged icon.
- Timers used during drag must be added to `.common` run-loop mode; scheduled default-mode timers may not fire while dragging.

### Drawer Model

- Drawer is app-centric: **one bundleID = one icon**. Use `LauncherChip`, not per-window `ChipView`.
- Drawer click is app-level: frontmost -> hide; otherwise unhide/open; not-running -> launch. Never reintroduce per-window drawer toggle.
- Launch-zone chips pass `isRunning: false` by zone, not live process state, or launch bounce stops too early.
- `DrawerOrderStore` is the single persistent display-order layer keyed by bundleID. Sync order over the member set (`drawerStore ∪ launchFavoriteStore`), not just visible icons.
- Same-zone reorder only: running-zone icons reorder with running-zone icons, launch-zone with launch-zone icons. Cross-divider drops are meaningless.
- `DragPayload` is generalized: strip id = stable chip token; drawer id = bundleID; `bundleID` is the cross-panel app key.

### Strip To Drawer

- `canStash` rejects only missing bundleID and `com.apple.finder`. Do **not** reject `isAppLevelFallback`; drawer running zone can render app-level icons.
- Drop zone is capsule visible content + small tolerance, plus drawer content only while open. Do not use full panel shadow frame or a wide tolerance.
- Strip-into-open-drawer converts on enter: add to `drawerStore`, flip payload to `.drawer`, then use normal drawer reorder. Revert on exit; only release inside commits.
- Enter/exit hysteresis is load-bearing; do not restore placeholder cells, `dropPreview`, `stashAtCommit`, or panel-resize-per-hover insertion.
- Spring-load is keyed on drag origin from strip, not live source after conversion.

### Drawer Back To Strip

- Precise drawer->strip landing applies only to running apps with at least one real live non-fallback window. Reject Finder, messaging special cases, app-level-fallback-only, and not-running stashes to old remove-on-release semantics.
- One drawer icon represents the app's whole window-chip block; land all chips contiguously in current display order.
- Landing goes through staged placement consumed inside `StripOrderStore.sync(current:appKeyOf:)`. Never write `liveOrder` outside sync before materialization.
- Convert/revert/commit ownership: convert removes from `drawerStore` and records converted bundle; realtime leave cancels external block before restoring drawer membership; normal mouse-up commits through `endDrag`.
- `DrawerView` membership safety cleanup must exempt converted-to-strip drags.
- Freeze strip width during any converted cross-panel drag; release or revert clears the clamp and relayouts once.
- Converted carrier visual and in-place gap must share `convertedRepresentative`; do not carry one chip while opening a gap at another.

## Pinned Folders And Folder Popup

### Pinned Folder Zone

- Strip layout is `[messaging][divider][shelf + pinned folders][divider][live windows]`; empty zones drop their adjacent divider (the shelf chip keeps the folder zone permanently non-empty).
- Folder chips drag via `DragController` source `.folder` (2026-07-06): in-zone reorder hit-tests **only** `folderChipFrames`; release clearly off the strip (dock target frame + 40pt) → unpin via the dedicated `onFolderDragEnded` callback. The `.folder` source must stay isolated from strip/drawer stash semantics — no drawerStore, no drop zones, no convert/revert, `canExternalDrop=false`, empty bundleID.
- Folder chip frames go into the separate `FolderChipFramePreferenceKey`/`folderChipFrames` (popup anchoring + external pin routing + folder reorder). Never merge folder ids into `ChipFramePreferenceKey`/`chipFrames` — that dict feeds live-zone drag-reorder and drawer-to-strip landing hit-tests.
- Per-folder sort (`FolderSortOrder`, chip menu 排序方式) persists in `PinnedFolderStore.sortOrders`; sorting is pure functions in `FolderContentsLoader.sorted(_:by:)` (kind sort = explicit rank tuple, **not** sentinel-prefixed strings — `localizedStandardCompare` ignores control characters). The chip cover follows the current sort's first **file** (`coverFile(in:order:)`); a sort change refreshes covers and re-opens an open popup in place.
- Finder windows do **not** expose their folder path to AX: `AXDocument` is listed but always `kAXErrorNoValue`; `AXProxy`/`AXTitleUIElement` carry only the display name (probed 2026-07-06). "Drag a Finder-window chip into the pinned zone to pin it" is therefore dead without Apple-Events/Automation permission — do not retry via AX.
- Covers come from `PinnedFolderCoverStore`: background enumeration plus a per-folder generation counter; async QL callbacks must re-check the generation before publishing, or stale thumbnails overwrite fresh covers. Do not enumerate directories or fetch icons synchronously on the main thread.
- `FolderCover.isThumbnail` decides rendering: real thumbnails get square-crop + border; icons render fit. Do not square-crop icon covers.
- `DirectoryWatcher`: the fd is closed only in the dispatch source's cancel handler; `stop()` is idempotent. Never close the fd before cancel.
- **Trash satellite is dead.** A full trash panel (drop-to-delete, full/empty icon, empty-trash, satellite geometry) was built and removed the same day (2026-07-06): owner judged it too heavy — always-on placement plus Full Disk Access / Automation permission demands. Implementation is archived in commit d7ae76e. Do not reintroduce without an owner decision.

### Folder Popup

- One shared lazy popup panel serves both folders and shelf — "only one popup at a time" falls out of the single-panel design. Lifecycle lives inside `PanelCoordinator` (needs private target frames / inhibitors); it clones the drawer recipe: plain `NSView` container + pinned `NSHostingView`, alpha fade, local+global `leftMouseDown` monitors.
- `dismissFolderPopupIfOutside` must exclude the anchor chip rect (+4pt tolerance): the monitor fires on mouseDown, the chip's tap on mouseUp — without the exclusion, clicking the same chip closes-then-reopens forever.
- The popup closes whenever the dock target frame changes (`layoutPanels`), on screen-parameter change, hover screen switch, fullscreen, or panel hide. Do not reposition it to chase an animating anchor.
- Popup layout mirrors native Stacks (owner 2026-07-06): **no header row**; "在访达中打开" is the grid's tail cell with the Finder icon; drill-in shows a floating back chip top-leading. Do not regress to a title/header design.
- Popup width is **derived** — column count = clamp(cell count, 3, 8), width computed from it (`FolderPopupStyle`, shared by folder + shelf popups; maxColumns=8 is the owner's "wider" decision — do not regress to 6). It is never a measured value; measured-width feedback loops cause `fittingSize` oscillation.
- Grid-cell context menus are hand-built via `FileItemMenuBuilder`. Close semantics are fixed: 打开/打开方式/在访达中显示 close the popup; 拷贝/复制路径/固定到固定区/移出中转 keep it open; 移到废纸篓 keeps it open (watcher refreshes; shelf also drops the entry). No Quick Look (nonactivating panel can't become key), no 显示简介, no rename.
- First-frame sizing: both popup and drawer measure `hosting.fittingSize` synchronously (`panel.layoutIfNeeded()`) **before** `orderFrontRegardless`, so the panel appears at its final size. The double-defer re-measure stays as fallback correction only. Do not go back to "open at last size, then snap-correct" — that jump was the owner-reported jank.
- Switching folders while the popup is open is an **in-place switch**: panel stays visible (alpha untouched), content swaps, frame animates from current to the new target, monitors reinstall. Never regress to orderOut-then-reopen — that blink was an owner complaint (可打断 2026-07-06).
- The popup must **preload folder contents before orderFront** (`PinnedFolderCoverStore` hot cache first, `FolderContentsLoader.preload` 150ms timeout fallback to async fill): first frame = complete grid at final size, panel enters as one solid unit with zero content changes during entrance ("整体一块" is the owner's acceptance bar). First-frame completeness includes file icons: warm the first visible batch through `FolderIconResolver` before presenting, and do not regress to "grid first, icons fade in from the top-left one by one" (owner-reported jank on 2026-07-07). First population never uses per-cell insertion animation (`animatesGridChanges` gate), and repositions within the 250ms entrance window are instant, never animated. Do not regress to "show first, fill later".
- Open/close + entrance animations use `PopoverAnimation` (fast ease-out, 0.18s open / 0.13s close). Taskbar width / panel-frame layout animation stays on `DrawerAnimation.duration` (0.22s), as do drawer-grid reorder animations. Never merge the two constant groups.
- Edge auto-hide is inhibited while the popup is open via `EdgeAutoHideInhibitor.folderPopupOpen`.

## Menus

### Native Chip Menus

- Strip and drawer chip menus are hand-built AppKit `NSMenu`, not SwiftUI `.contextMenu`.
- Do not revert to SwiftUI context menus; they cannot do native Option alternate items after the menu opens.
- `MenuHostNSView` overlay claims only right-click / Control-click and returns `nil` from `hitTest` otherwise. Do not widen it to swallow normal left-click or drag events.
- Force Quit is a native alternate item after Quit, gated out for this app itself.
- Finder menu items (`前往文件夹…`, `连接服务器…`) apply to both persistent Finder chip and concrete Finder windows.
- Recent files/folders are best-effort only. Per-app `.sfl*` lists and Finder `FXRecentFolders` may fail; failures must produce an empty section, never block the menu. Do not retry private Dock hooks, browser history DBs, or Adobe private prefs as "public" features.

## Panel Geometry And Visibility

### Shadow Padding

- SwiftUI shadow margin is `shadowPadding = 20pt`.
- Floating panels (popup, drawer) must keep shadow extent `radius + |y-offset| ≤ shadowPadding`, or the shadow hard-clips at the panel edge (owner-reported 裁切感; current values 12/5). The bottom strip may exceed it because its clip zone sits below the screen edge.
- Coordinate math on `dockFrame` / `capsuleFrame` must subtract `shadowPadding` to reach visual content.
- `fittingSize.width` must subtract `2 * shadowPadding`.

### Relayout

- Relayout is target-frame-driven. Never position one panel from another panel's live `.frame` during animation.
- Compute dock/capsule/drawer target frames via pure target functions; animate all panels in one `NSAnimationContext`.
- Content changes animate; open, screen changes, hover-switch, and first layout are instant.
- Drop zones and drawer-open checks read stored target frames, not live frames.
- Drawer window content must be a plain `NSView` container with the `NSHostingView` pinned inside. Do not make `NSHostingView` the direct `contentView`; AppKit top-anchors content growth and causes the drawer downward dip.

### Multi-Screen Placement

- All placement panels (dock, capsule, drawer, drag carrier) must be `NonConstrainingPanel`, never plain `NSPanel`.
- Bottom-anchored panels use `screen.frame`, not `screen.visibleFrame`, for bottom Y and horizontal clamp.
- Keep `visibleFrame` only for the drawer top/menu-bar height cap.
- Hover screen switching uses dwell (~350ms), not instant edge-trigger.
- Fullscreen hide hides the capsule and closes the drawer too; do not leave capsule floating alone.

### Fullscreen Detection

- `FullscreenWindowClassifier.isFullscreen` is the single AX fullscreen predicate.
- Its `role == kAXWindowRole` gate is load-bearing. Only real `AXWindow` elements may reach frame≈screen fallback.
- Do not tighten the gate to subrole; minimized Finder windows can report `AXDialog`, while desktop pseudo-windows may have no readable subrole.
- Do not use `NSWorkspace.frontmostApplication` in fullscreen decision paths. Use notification PID or a fresh active-app scan.

## Settings And Compatibility

### Status Menu / Edge Auto-Hide

- Do not reintroduce the multi-display strategy menu; runtime behavior is fixed to dwell hover-switch.
- Native Dock slider applies only on commit, never continuously while dragging. Do not restore a separate apply item or confirmation dialog unless owner changes product decision.
- Native Dock writes are non-sandbox only; keep the sandbox entitlement gate.
- Tungsten Edge slider controls wake delay, not hide delay. Finite wake delay is `0.1s...3.0s`; `不唤醒` still allows hide but disables bottom-edge wake.
- Hidden-state bottom-edge detection is load-bearing and must keep probing while the dock panel is hidden.

### Minimum OS

- Minimum deployment target is **macOS 12**. Do not use macOS 13+/14+ APIs unguarded.
- Guard newer APIs with availability checks and a Monterey-compatible fallback.
- Known converted APIs: `defaultScrollAnchor`, new two-parameter `onChange`, `Task.sleep(for:)`.
- Old single-value `onChange` deprecation warnings are expected back-deployment noise.

## Collaboration Rule

The project owner directs product but does not read code and does not read English comfortably. Reply in Chinese.

- Status updates and results should first explain behavior in plain Chinese, then add file/API details if useful.
- Choices should be framed as product behavior and trade-offs, not implementation trivia.
- For coding tasks, read code first and implement through the repo's existing patterns.
- For "打检查点", create a local git commit unless the user says otherwise; do not push or create PRs unless asked.
