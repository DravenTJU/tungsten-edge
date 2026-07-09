# AGENTS

> **New agent: read this first.**
> Product state and decisions live in the owner's Obsidian vault:
> `/Users/caye/Documents/Obsidian Vault/Projects/macos-dock-cc-v2/`, entry note `00 macos-dock-cc-v2 总览.md`.
>
> This file is only for engineering guardrails that should not be rediscovered or reverted. Active repo-local references live in `Docs/`; historical notes live in `Docs/Archive/`.

## Source Of Truth

- Product state / decisions: Obsidian entry note.
- Engineering hard constraints: this file.
- Platform quirks: `Docs/05-known-platform-quirks.md`.
- Trust model history: `Docs/Archive/Engineering/19-taskbar-trust-incident.md`, `Docs/Archive/Engineering/20-inventory-first-taskbar-trust.md`.
- Focus debug history: `Docs/22-window-focus-flicker-debugging.md`.
- Finder P0 records: `Docs/Archive/Engineering/17-finder-p0-implementation.md`, `Docs/Archive/Engineering/18-real-sample-finder-findings.md`.

## Taskbar Trust And Placement

- This app is an inventory-first bottom taskbar for real user-operable windows. Do not return to broad bottom-up CG/AX admission.
- Minimize, hide, and temporary CG disappearance do not release a strip slot. Only true close releases it.
- Do not reintroduce held-slot TTL or "expire then return to tail" as the default placement rule.
- Filter system internals, widgets, app extensions, transparent/fake surfaces before any keep-slot or disappeared retention.
- `WorkspaceSource` starts from `NSWorkspace` regular apps, reads `AXWindows`, and emits `.appWindowInventory`.
- Inventory reads keep the existing 100ms per-app timeout, 12 concurrent app reads, and 30-round unread degradation before CG can decide whether windows still exist.
- While inventory-first is enabled, CG and generic `.accessibility` observations may prove/enrich inventory entries but must not create ordinary strip entries. Reduced-permission mode may create CG fallback entries.
- Keep rollback flags working: `DOCK_INVENTORY_FIRST_ENABLED=0`, `DOCK_AX_ADMISSION_MODE=legacy`.
- Long-gap duplicate prevention: before creating a new identity, conservatively match same process/app against current seats by title + nearby frame; ambiguous candidates do not merge. Details: `Docs/Archive/Engineering/21-long-gap-duplicate-card-fix.md`.

## App Rules

- Finder always keeps a persistent strip slot. `seedRunningApps` adds Finder even when all Finder windows are closed.
- Closed-window Finder uses `app-com.apple.finder`; clicking it opens the home directory. Never plan hide/minimize for this persistent `app-*` chip.
- Process-death reconcile must not remove Finder's app entry. Finder process existence alone does not imply a concrete Finder window.
- Concrete Finder folder windows remain window-level items when title/frame are available. If a specific Finder target cannot be captured, do not fall back to whole-app activation.
- Finder minimize feedback accepts either `minimized` or temporary `disappeared`.
- Finder window content preview must not rely on AX folder-path attributes. Treat AX document/URL as opportunistic only; current reliable path is AppleEvents enumeration matched by Finder window title + frame, and ambiguous/no matches must fail.
- Finder AppleEvents parsing and title+frame matching live in `FinderAppleEventMatcher` with unit coverage. `FinderWindowContentsReader` should stay the I/O layer for AX lookup, Automation permission, and AppleScript execution.
- Feishu window-level handling is opportunistic. If samples are weak, titles generic, or frontmost AX unreliable, fall back to one stable app-level item.

## Window Identity And Actions

- Native tabs use a **single-seat** model: one physical window = one seat = one chip. Background native tabs are not separate strip items.
- Seat identity is `tabgrp-<pid>-s<serial>` from a monotonic counter. Never derive stable identity from `cgWindowID`.
- `WindowRecord.id` may be `cgw-<activeCgID>`, but chip identity is `groupID = seat.token`; action target is the current active cgID.
- Tab switch may adopt a new active cgID into the same seat only when exactly one seat claims the same frame.
- Tear-out keeps the old-frame seat for the new active tab; the moved old active cgID becomes a fresh seat.
- Minimized multi-tab windows may expose all tabs as eligible AX windows. Fold background tabs into the placed minimized seat by exact frame first, then by `min=true` + off-screen + same size.
- A strip chip id is a stable identity token, not necessarily actionable. All strip show/hide/minimize/toggle calls must use `item.actionWindowID`.
- `StripItem.pid`, `StripItem.cgWindowID`, and `StripItem.bounds` are current representative live facts for action/preview targeting only. Never use them as chip identity or persistent order keys.
- Drawer actions are app-centric and must not use strip chip ids for window-level toggle.

## Focus And Action Planning

- Minimizing the frontmost focused window A1 of multi-window app A should return focus to the previous other app B, not sibling A2.
- Only fire that background activation path when the target is the frontmost app's focused AX window. Right-click-minimizing a non-focused sibling must not steal focus.
- `postSkyLightWindowFocus` is the shared focus core. Its private byte layout is load-bearing; do not simplify or gate fallback on nonzero private return codes.
- Early focus applies only to `.activateWindow`, cross-app, visible active/inactive windows, using snapshot `record.cgWindowID` before handle capture.
- Minimized restore is restore-then-switch, never switch-early. Exclude `.minimized` from early focus; after restore, immediately call `postSkyLightWindowFocus` with the snapshot wid, then set `kAXMainAttribute=true`.
- Action-decision paths must not use `NSWorkspace.frontmostApplication`; read `NSRunningApplication(processIdentifier:)?.isActive` fresh.
- Keep kill switch `DOCK_SKYLIGHT_FOCUS=0`.
- Optimistic state predicts **status only** for show/hide style actions and clears on snapshot confirmation or timeout. Do not re-add predicted `isAppFrontmost`.
- The chip tap pulse is view-local acknowledgment only. It must not feed planner state or any frontmost decision.

## Drag, Drawer, And Ordering

- Do not use SwiftUI `.onDrag` / `NSItemProvider` or AppKit `beginDraggingSession` for local strip, drawer, or folder chip drags. The visual carrier is owned by `DragController`.
- Real file drag-out/in is exempt: file grid cells may use system drag payloads, and SwiftUI file `.onDrop` destinations are allowed.
- Strip reorder uses one `"strip"` coordinate space for chip frames, cursor location, and floating copy.
- Chip frames are read via `.background` GeometryReader, not `.overlay`. Keep `grabOffset`, mouse-up fallback, and vanished-window cleanup.
- `DragController` remains the single authority for monitors, carrier `NSPanel`, coordinate conversion, drop decisions, and idempotent teardown.
- Carrier position and cross-panel hit testing use `NSEvent.mouseLocation` screen coordinates.
- Timers used during drag must be added to `.common` run-loop mode.
- Drawer is app-centric: one bundleID = one `LauncherChip`. Drawer click is app-level frontmost->hide, otherwise unhide/open; not-running->launch.
- `DrawerOrderStore` is the persistent ordering layer keyed by bundleID and synced over `drawerStore ∪ launchFavoriteStore`.
- Drawer reorder is same-zone only. Cross-divider drops are meaningless.
- `DragPayload` uses strip id = stable chip token, drawer id = bundleID, folder id = folder path.

## Strip And Drawer Conversion

- `canStash` rejects only missing bundleID and `com.apple.finder`. App-level fallback chips can be stashed.
- Strip-to-drawer drop zone is visible capsule content plus small tolerance, and drawer content only while open. Do not use full shadow frame as the hit zone.
- Strip-into-open-drawer converts on enter, reverts on exit, and commits only on release inside. Keep enter/exit hysteresis; do not restore placeholder cells or resize-per-hover insertion.
- Drawer-to-strip precise landing applies only to running apps with at least one real live non-fallback window. Reject Finder, messaging special cases, app-level-fallback-only, and not-running stashes.
- One drawer icon represents the app's whole window-chip block; land all chips contiguously in current display order.
- Drawer-to-strip landing goes through staged placement consumed inside `StripOrderStore.sync(current:appKeyOf:)`.
- Freeze strip width during converted cross-panel drags and release the clamp only on commit or revert.

## Pinned Folders And External File Drop

- Strip layout is `[messaging][divider][shelf + pinned folders][divider][live windows]`; empty zones drop adjacent dividers, while shelf keeps the folder zone non-empty.
- Folder chips drag via `DragController` source `.folder`; keep it isolated from strip/drawer stash semantics.
- Fixed-folder primary click behavior must route through `FolderInteraction.primaryAction`; do not scatter left-click policy across views. Current default is preview toggle, with Finder open available from the menu.
- Folder reorder and popup anchoring use `folderChipFrames`. Never merge folder ids into `ChipFramePreferenceKey`/`chipFrames`.
- Per-folder sort persists in `PinnedFolderStore.sortOrders`; covers follow the current sort's first **file**.
- Fixed folder chips render as a flat single cover with 36/24 sizing. Do not restore stacked-paper layers.
- Finder windows do not expose folder paths reliably through AX. Do not retry Finder-window-chip-to-pinned-folder via AX without an owner decision.
- `PinnedFolderCoverStore` must keep background enumeration and generation checks so stale async thumbnails cannot overwrite fresh covers.
- `FolderCover.isThumbnail` decides rendering: thumbnails get square-crop + border; icons render fit.
- `DirectoryWatcher.stop()` is idempotent; the fd closes only in the dispatch source cancel handler.
- The strip `.onDrop` for external files must stay on the same view level that declares the `"strip"` coordinate space, before shadow padding.
- External drop routing stays in pure, unit-tested `StripDropRouting.route`: shelf hit -> stash, folder-zone x-range + 24pt tail slack -> pin, else reject.
- Only directories can pin; files dropped on the folder zone are a silent no-op. Re-dropping an already-pinned folder repositions it.
- External drop hover cleanup must not rely only on `performDrop` / `dropExited` or `folderPaths` changes. Keep `dropEntered` gating plus `.common` Timer watchdog for missing terminal callbacks and post-drop hover flicker.
- Middle-click / Force Click content-preview monitors must observe and return the original `NSEvent`. They must not consume left clicks, break folder drag, or feed planner/frontmost state.

## Shelf And Folder Popup

- Shelf stores references only, newest first. Never move/copy files implicitly. `ShelfStore.prune()` runs when opening the shelf popup.
- Shelf chip is a fixed head of the pinned-folder zone: click + drop target only, never draggable and never a `DragController` source.
- Folder and shelf share one popup panel through `PanelCoordinator.PopupContent`; preserve the one-popup-at-a-time invariant.
- Popup lifecycle stays in `PanelCoordinator`: plain `NSView` container, pinned `NSHostingView`, alpha fade, local/global left-mouse monitors.
- `dismissFolderPopupIfOutside` must exclude the anchor chip rect with tolerance so clicking the same chip does not close-then-reopen.
- Popup closes on dock target-frame change, screen-parameter change, hover screen switch, fullscreen, or panel hide. Do not chase an animating anchor.
- Popup layout mirrors native Stacks: no header row; Finder open is the grid tail cell; drill-in uses a floating back chip.
- Popup width is derived from `FolderPopupStyle`: column count = clamp(cell count, 3, 8). It is not measured feedback.
- Grid-cell menus are hand-built via `FileItemMenuBuilder`; no Quick Look, Get Info, or rename in the nonactivating panel.
- First frame must be complete before `orderFront`: preload folder contents, warm visible icons, use synchronous `fittingSize`, and avoid first-population insertion animation.
- Switching folders while popup is open is an in-place content/frame switch, not orderOut-then-reopen.
- Popup open/close animation uses `PopoverAnimation`; taskbar/drawer layout animation stays on `DrawerAnimation`.
- Edge auto-hide is inhibited while the popup is open via `EdgeAutoHideInhibitor.folderPopupOpen`.

## Menus, Panels, And Screens

- Strip and drawer chip menus are hand-built AppKit `NSMenu`, not SwiftUI `.contextMenu`.
- `MenuHostNSView` claims only right-click / Control-click and returns `nil` from `hitTest` otherwise.
- Force Quit is a native alternate item after Quit, gated out for this app itself.
- `LauncherChip` menu running-state follows the passed-in `isRunning` (the displayed zone), never an independent `NSWorkspace` process query. A launch-zone icon whose process is still alive (window-closed / background) must not surface 显示/隐藏/退出. The pure decision is `LauncherMenuPlan.itemKinds` (unit-tested); `buildLauncherMenu` only renders it and queries `NSWorkspace` solely to obtain the app object for an action it already decided to show. Pure launch-favorite chips use `menuMode = .removeOnly`; membership items are injected via `membershipItems` and may be multiple (a stashed+pinned icon shows both 移回任务栏 and 取消固定).
- Finder menu items apply to both persistent Finder chip and concrete Finder windows.
- SwiftUI shadow margin is `shadowPadding = 20pt`; floating panel shadows must fit within it.
- Coordinate math on `dockFrame` / `capsuleFrame` subtracts `shadowPadding` to reach visual content, and `fittingSize.width` subtracts `2 * shadowPadding`.
- Relayout is target-frame-driven. Do not position one panel from another panel's live `.frame` during animation.
- Drawer window content must be a plain `NSView` container with the `NSHostingView` pinned inside.
- Placement panels use `NonConstrainingPanel`, not plain `NSPanel`.
- Bottom-anchored panels use `screen.frame` for bottom Y and horizontal clamp; reserve `visibleFrame` for drawer top/menu-bar height cap.
- Hover screen switching uses dwell, not instant edge-trigger.
- Fullscreen hide hides capsule and closes drawer. `FullscreenWindowClassifier.isFullscreen` remains the single AX predicate, gated to real `AXWindow` roles.

## Settings And Compatibility

- Do not reintroduce the multi-display strategy menu; behavior is fixed to dwell hover-switch.
- Native Dock slider applies only on commit and remains non-sandbox gated.
- Tungsten Edge slider controls wake delay, not hide delay. `不唤醒` still allows hide but disables bottom-edge wake.
- Hidden-state bottom-edge detection must keep probing while the dock panel is hidden.
- Minimum deployment target is **macOS 12**. Guard newer APIs with availability checks and Monterey-compatible fallbacks.
- Old single-value `onChange` deprecation warnings are expected back-deployment noise.

## Collaboration Rule

The owner directs product, does not read code, and does not read English comfortably. Reply in Chinese.

- Explain behavior in plain Chinese first; add file/API details only when useful.
- Frame choices as product behavior and trade-offs, not implementation trivia.
- For coding tasks, read code first and follow existing repo patterns.
- For "打检查点", create a local git commit unless told otherwise; do not push or create PRs unless asked.
- For neat-freak / 洁癖 / 收尾 / 整理文档, do not expand this file by default. Update `AGENTS.md` only for new hard engineering guardrails that would prevent code regressions. Product state, roadmap, release progress, decision history, and long handoff text belong in Obsidian; historical notes belong in `Docs/Archive/`.
