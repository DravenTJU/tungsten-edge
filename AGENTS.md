# AGENTS

> **New agent: read this first.**
>
> **What this app is**: Tungsten Edge 钨极 is a window-oriented bottom taskbar for macOS, designed to replace the system Dock. Multi-window apps normally split into separate window chips, with deliberate app-level entries for Finder, messaging apps, kept apps (user-chosen「在程序坞中保留」), and compatibility fallbacks. It also includes a drawer for stashed apps and a pinned-folder zone. Minimum deployment target: macOS 12.
>
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
- `AppTracker` is the sole window-inventory authority: it seeds from `NSWorkspace` regular apps, reads `AXWindows` per app, and owns seat state. The old `WorkspaceSource` / observation-pipeline inventory path was replaced by `AppTracker + AppWindowObserver` (ef50008, 2026-05-31); `WorkspaceSource` is deleted. The remaining old pipeline types (`ObservationPipeline`, `WindowIdentityEngine`, `LifecycleTransitionEngine`, `ObservationAdmissionGate`) are not instantiated by the app — only WindowLab and legacy tests use them (removal is 方案 A step 2, pending).
- Inventory reads keep the 100ms per-app AX messaging timeout (seed probes and `scanNonAdmittedApps`). Slow/hung apps are skipped at seed and picked up by the post-launch scan rounds; CG full-list presence — not AX absence — decides whether a window still exists.
- `seedRunningApps` subscribes workspace notifications **before** seeding so launch/exit events during seed are not lost. Seed probes use `inventoryWindows(forPID:messagingTimeout:)` with env `DOCK_SEED_AX_TIMEOUT_MS` (0 = legacy no-timeout, other = ms override). Probed windows are admitted directly via `reconcileSeats(preloadedEligible:)` without a second untimed AX read. Keep kill switch `DOCK_SEED_AX_TIMEOUT_MS=0`.
- `start()` schedules four rounds of `scanNonAdmittedApps()` at 0.5/1/2/4s post-launch to catch apps that were slow to respond during seed.
- CG signals (full window list, on-screen set) may prove, retain, or veto seats but must never create them; seats are created only from eligible AX windows.
- The old rollback flags `DOCK_INVENTORY_FIRST_ENABLED` / `DOCK_AX_ADMISSION_MODE` are defunct: their only reader is the un-instantiated legacy gate. Do not promise or rely on them. Working kill switches: `DOCK_SEED_AX_TIMEOUT_MS=0`, `DOCK_SKYLIGHT_FOCUS=0`.
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
- Messaging identity is persistent (owner 2026-07-12 #2): a messaging app stays in the messaging zone even when not running — gray, click-to-launch — and keeps its messaging flag throughout. `partitioned()`'s messaging filter is `!drawerStore.contains($0)` only (no running/snapshot gate). **Drawer is the exception**: a messaging app stashed in the drawer hides from the zone (shows in the drawer); dragging it back restores the zone. The `.messagingApp` no-main-window branch handles all three states — running-with-main (ChipView), running-no-window (`isRunning:true`, tap → `reopenMainWindow`), not-running (`isRunning:false`, `onLaunch: runtime.beginLaunch`, never `reopenMainWindow`).

## Window Identity And Actions

- Native tabs use a **single-seat** model: one physical window = one seat = one chip. Background native tabs are not separate strip items.
- Seat identity is `tabgrp-<pid>-s<serial>` from a monotonic counter. Never derive stable identity from `cgWindowID`.
- `WindowRecord.id` may be `cgw-<activeCgID>`, but chip identity is `groupID = seat.token`; action target is the current active cgID.
- Tab switch may adopt a new active cgID into the same seat only when exactly one seat claims the same frame.
- Tear-out keeps the old-frame seat for the new active tab; the moved old active cgID becomes a fresh seat.
- Minimized multi-tab windows may expose all tabs as eligible AX windows. Fold decision lives in pure `TabFoldDecision` (unit-tested), four levels: seat membership history (`formerCgIDs`), then shadow-tab pool, then exact frame, then `min=true` + off-screen + same size. Do not make geometry or the placed seat's min flag a hard precondition again.
- `formerCgIDs` membership is **session-local** (wiped on every dock restart) — never rely on it alone for fold correctness; the shadow pool is the restart-safe layer. Hygiene is load-bearing against cgID reuse: record on tab-switch adoption only (tear-out expulsion must NOT record), purge on window destroy (`purgeFromSeatHistories`) and by intersection with the CG full list on every reconcile.
- Shadow-tab pool (`AppEntry.shadowTabCgIDs`): ids present in the CG layer-0 list for the pid but absent from AXWindows — the unique signature of order-out background tabs (real windows stay in AXWindows whether visible, minimized, hidden, or on another Space; verified live against ChatGPT/Finder/Ghostty 2026-07-13). Verdicts must use the **previous** round's pool (the minimize burst floods AX in the current round); ids leave the pool on true close or on appearing in AX with `min=false` (never on `min=true` appearance); pool update is skipped when AX returned zero windows while CG still has some (hung app); pool folding needs ≥1 placed seat and a `min=true` candidate (tear-out landing must still split a card).
- Phantom-seat healing (`PhantomSeatDecision`, unit-tested): a seat may be released from the min/hidden retention branch only when ALL five gates pass — never seen `min=false` in AX this session (`everSeenVisible`, protects Safari-style windows that leave AX when minimized), AX-absent ≥ `phantomReapGrace` (10s), cgID still in CG, the AX read saw windows, and ≥1 sibling seat currently AX-present (a lone seat never heals). Do not loosen these gates; healing exists because seed-time minimized tab groups can split (no history, no pool) and the phantoms are otherwise held forever by min retention.
- The `[tabfold]` split-point and `[tabheal]` prints are permanent anomaly-path diagnostics (zero output on normal paths). Do not remove them as "诊断遗留" — the 871305d cleanup left the 2026-07-13 recurrence with no forensic evidence.
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

## Taskbar Interaction Performance

- `ScreenRectReader` has two deliberate delivery modes. Taskbar and drawer roots use `.root`: every distinct rect is captured and delivered in order. The title tooltip alone uses `.tooltip`: a 50ms trailing debounce that resets its deadline on every change. Every queued delivery owns a cancellable handle; detach, dismantle and delivery-mode changes cancel all pending work. Callbacks read the latest closure when they execute. Do not replace either mode with a shared `DispatchQueue.main.async` probe.
- Chip hover presentation has one animated scalar (`ChipHoverProgress.animatableData`). Pill height/shift, icon size, subtitle width/opacity, fill and rim all derive from the same `ChipHoverVisual`; icon-only, titled and launcher chips share it. Do not add per-property hover `.animation` modifiers. Press feedback remains a separate spring with its existing parameters. `DOCK_CHIP_ANIM_TRACE=1` is the default-off presentation trace.
- One `DockStripView.body` evaluation builds exactly one `StripProjection`, and only that builder may call `StripItem.items(from:)` for the render pass. Rendering, ordering and drag callbacks consume the captured projection; do not reintroduce computed properties that rebuild it. `DockSnapshot` publications are equality-gated. Feedback/debug text lives in `DebugRuntimeState`, not the taskbar's `AppRuntime.objectWillChange` channel. Accessibility trust in snapshot handling comes from the injected cached reader, never a synchronous trust query.
- AX event inventory (`windowCreated`, focus and title changes) is a 100ms background read with one in-flight read per pid plus exactly one trailing read for a burst. Results carry `pid + POSIX process identity + mutation generation`; destroy, minimize/deminiaturize, exit and pid reuse invalidate older results. `DOCK_EVENT_AX_ASYNC=0` is the synchronous compatibility path. An `.unread` reconcile round is wholly unknown: preserve seats, absence clocks, shadow pool and phantom state without advancing any of them. A successful empty read keeps the existing shadow-pool health rules.
- Window actions try the known cgWindowID handle under one 100ms total budget, then use the existing full title/frame chain; `DOCK_FAST_WINDOW_HANDLE=0` disables the fast attempt. `DOCK_CHIP_PROBE` defaults off and only `=1` may add planner/minimize diagnostic reads. If a `.minimizeWindow` handle cannot be captured, return failure and let optimistic UI roll back; never hide the whole app unless temporary compatibility switch `DOCK_MINIMIZE_APP_FALLBACK=1` is set.

## Drag, Drawer, And Ordering

- Do not use SwiftUI `.onDrag` / `NSItemProvider` or AppKit `beginDraggingSession` for local strip, drawer, or folder chip drags. The visual carrier is owned by `DragController`.
- Real file drag-out/in is exempt: file grid cells may use system drag payloads, and SwiftUI file `.onDrop` destinations are allowed.
- Strip reorder uses one `"strip"` coordinate space for chip frames, cursor location, and floating copy.
- Chip frames are read via `.background` GeometryReader, not `.overlay`. Keep `grabOffset`, mouse-up fallback, and vanished-window cleanup.
- `DragController` remains the single authority for monitors, carrier `NSPanel`, coordinate conversion, drop decisions, and idempotent teardown.
- Carrier position and cross-panel hit testing use `NSEvent.mouseLocation` screen coordinates.
- Timers used during drag must be added to `.common` run-loop mode.
- Cross-screen chip drag is **never** supported. `DragController.activeScreenID` is fixed at `beginDrag` to the origin screen and owns arbitration for the whole drag; every `DockStripView` instance must short-circuit its `onChange(globalLocation)` fan-out, its `messagingZoneIDs` cancel watcher, and its capsule/strip drop highlights unless it owns the drag — otherwise the off-cursor screen reverts the in-flight conversion and N capsules glow at once. Drop zones and spring-load hit tests read the **origin** bar's target frames; the carrier panel stays single-screen by policy, not by accident.
- Drawer is app-centric: one bundleID = one `LauncherChip`. Drawer click is app-level frontmost->hide, otherwise unhide/open; not-running->launch.
- Drawer two zones are partitioned by process state from `RunningApplicationStore`: upper zone = running (bright + white dot), lower zone = not-running (gray, no dot). `isLaunchingWithoutWindow` gating still applies.
- `DrawerOrderStore` is the persistent ordering layer keyed by bundleID and synced over `drawerStore - keptAppStore`.
- Drawer reorder is same-zone only. Cross-divider drops are meaningless.
- `DragPayload` uses strip id = stable chip token, drawer id = bundleID, folder id = folder path, messaging id = bundleID.
- Messaging-zone chips are draggable: in-zone reorder persists to `MessagingAppStore.bundleIDs` (`reorder` operates on the full array so hidden members keep relative positions). Frames report into the separate `MessagingChipFramePreferenceKey` — never merge messaging ids into `chipFrames`.
- Messaging reorder (like drawer reorder) is driven by `onChange(globalLocation)` (`updateMessagingReorder`), never by the chip's own `DragGesture.onChanged` — SwiftUI cancels the gesture after the first reorder moves the chip.
- `.messaging` drop zones equal `.strip` (capsule + open drawer body). The strip itself is never a `.messaging` drop target; releases on shelf/folder zone/live zone/desktop are no-ops. Spring-load and `isOverStashZone` accept `.messaging` alongside `.strip`.

## Strip And Drawer Conversion

- `canStash` rejects only missing bundleID and `com.apple.finder`. App-level fallback chips can be stashed.
- Strip-to-drawer drop zone is visible capsule content plus small tolerance, and drawer content only while open. Do not use full shadow frame as the hit zone.
- Strip-into-open-drawer converts on enter, reverts on exit, and commits only on release inside. Keep enter/exit hysteresis; do not restore placeholder cells or resize-per-hover insertion.
- Drawer membership **is** 「在程序坞中保留」 (owner 2026-07-11): the menu vocabulary has exactly two verbs — 在程序坞中保留 (join, only on non-member window chips) and 从程序坞中移除 (the only menu exit). 收进抽屉/移出抽屉 must not reappear in any menu; placement changes are drag-only. **从程序坞中移除 shows only when the app is NOT running** (owner 2026-07-12 #1): not-running drawer icons (lower zone) and not-running kept placeholders. Running chips (window cards, upper-zone drawer icons, running kept icons) never surface it — move a running app out of the dock by dragging (drawer → drag out; kept → quit first, then remove the gray icon). The removal action itself is unchanged/immediate; only the menu entry is gated. Window cards are always running → never carry 从程序坞中移除.
- Cross-panel conversion state is the single `DragController.conversion: CrossPanelConversion?` enum (stripToDrawer / drawerToStrip / messagingToDrawer / drawerToMessaging) — original payload + rollback snapshot, no parallel boolean flags. Mutation order in every convert/revert: set `conversion` and flip/restore `draggingPayload` **before** touching stores, so member-vanish watchers exempt by payload source (no cancel race).
- Drag conversions are **symmetric transactions**: strip→drawer does `drawer.add + kept.remove` on convert, `kept.add + drawer.remove` on revert; capsule drop does `drawer.add + kept.remove`. Drawer→strip keepPlacement does `drawer.remove + kept.add` on enter, `kept.remove + drawer.add` on revert. Messaging→drawer does `drawer.add` on enter (messaging flag untouched), `drawer.remove` on revert; drawer→messaging does `drawer.remove` on release, `drawer.add` on revert. `cancelDrag` must rollback any uncommitted transaction via the same revert paths before teardown.
- Drawer-to-strip modes come from pure `DragConversionPlan.drawerDragOutMode` (unit-tested; messaging check must precede the real-window check): Finder / not-running messaging → reject; running messaging → releaseToMessaging; running with real windows → unstash (existing precise landing); not-running/no-real-window → keepPlacement. Reject is the only branch that does nothing — a messaging member never takes the fallback unstash on strip drop (`DragConversionPlan.endAction` gates it).
- releaseToMessaging triggers on entering the **messaging-zone range** (union of messaging chip frames + 8pt enter / 24pt exit hysteresis; 56pt strip-head fallback when the zone is empty), not on leaving the drawer body. Leaving the range or entering a drop zone reverts to the drawer.
- One drawer icon represents the app's whole window-chip block; land all chips contiguously in current display order. keepPlacement uses a single-element block `["app-\(bundleID)"]` when no window cards exist.
- Drawer-to-strip landing goes through staged placement consumed inside `StripOrderStore.sync(current:appKeyOf:)`. The sync fallback resolves kept placeholder ids when no window cards match the bundleID.
- Freeze strip width during converted cross-panel drags and release the clamp only on commit or revert.

## Kept Apps

- A kept app does **not** absorb live windows: while running with real windows it shows ordinary window chips; only when exited (or running with no real window) does it collapse to a single app-level icon that stays in place (gray + click-to-relaunch when exited). The icon lives in the live zone and can be freely dragged/reordered like window chips.
- Finder must never enter kept state. Reject `com.apple.finder` both when loading `KeptAppStore` and when adding through any menu/action path.
- Kept identity wins over drawer and messaging membership. Route conversions through `AppMembershipController`; keeping a messaging app deliberately calls `unmark` and therefore keeps its auto-registration opt-out after later removal.
- `removeFromDock` is the universal exit: `kept.remove + drawer.remove + messaging.unmark` (unmark records the opt-out so autoRegister does not silently re-add; manual 标记为消息应用 brings it back). Not-running drawer icons route their 从程序坞中移除 item through this controller method — never call `drawerStore.remove` directly from a menu; running drawer icons show no membership item.
- `.keptApp` projection has two sources, both rendered as `LauncherChip` with `RunningApplicationStore` running dot/gray/hidden state: (a) unrunning kept apps → placeholder injection by `DockStripView` (id `"app-\(bid)"`); (b) running kept apps whose only snapshot entry is `isAppLevelFallback` → that entry is re-typed to `.keptApp` in the strip projection (id unchanged from the snapshot's `app-*` fallback token). The id `"app-\(bid)"` matches `AppTracker.rebuildSnapshot()`'s no-window fallback token — this is the position-retention lifeline.
- Clicking a running kept app with no real non-fallback window must unhide/reopen it. Running kept apps with real windows use app-level frontmost->hide and background->show behavior.
- Kept-app actions do not write window-level optimistic state or predicted frontmost state. Any immediate acknowledgment stays view-local, and app-active decisions read a fresh `NSRunningApplication`.
- Messaging auto-registration filters kept apps on every snapshot update. Startup reconciliation and display projection remain defensive layers against conflicting persisted memberships.
- Position retention: on app exit, window-card ids enter the 5s grace period in `StripOrderStore`; the `app-*` placeholder appears the same frame. `StripOrdering.reconcile` inserts the placeholder after the app's rightmost window card using sticky appKey memory. Sticky appKey is pruned to `current ∪ liveOrder` keys after each sync. `persistableLiveOrder` saves `tabgrp-*` + kept `app-*` only; `kern.boottime` guard discards the entire order on machine restart. Cold-start placeholders land at the live zone head.
- Messaging pop-out windows land at the **live-zone head** (owner 2026-07-12 #4): `StripOrdering.reconcile` takes `headPreferredKeys` — a new (unremembered) window with no live-zone sibling whose appKey is in that set inserts at head (after existing head-preferred windows, keeping their relative order) instead of the tail. `StripOrderStore.reconciled` and `sync` **must be fed the identical set** (`Set(messagingStore.bundleIDs)`) at both DockStripView call sites — a mismatch makes the window head on first frame then jump on sync. Only affects new ids; a dragged/remembered messaging window keeps its position.
- Kept app chips participate in the live-window drag/reorder and drawer-conversion paths. Drag conversions are symmetric transactions (see Strip And Drawer Conversion above).

## Pinned Folders And External File Drop

- Strip layout is `[messaging][divider][shelf + pinned folders][divider][live windows]` (kept-app placeholders live in the live zone, not the messaging zone); empty zones drop adjacent dividers, while shelf keeps the folder zone non-empty. Zone contents are screen-filtered per **Per-Display Taskbar** below; ordering runs on the global list first, filtering second.
- Folder chips drag via `DragController` source `.folder`; keep it isolated from strip/drawer stash semantics.
- Fixed-folder primary click behavior must route through `FolderInteraction.primaryAction`; do not scatter left-click policy across views. Current default is preview toggle, with Finder open available from the menu.
- Folder reorder and popup anchoring use `folderChipFrames`. Never merge folder ids into `ChipFramePreferenceKey`/`chipFrames`.
- Per-folder sort persists in `PinnedFolderStore.sortOrders`; covers follow the current sort's first **file**.
- Fixed folder chips render as a flat single small cover with the folder name always visible below it. Do not restore hover-only names, 36/24 hover resizing, or stacked-paper layers.
- Folder-chip hover feedback (whole-chip scale-up anchored to the bottom) and the drop-target highlight are non-layout visual overlays only (`scaleEffect`): they must never change the chip's layout size or the reported drop-hit frame. The resident name row stays truncated; the full name comes from the `.help` tooltip, never by widening the chip or unclipping that row.
- Finder windows do not expose folder paths reliably through AX. Do not retry Finder-window-chip-to-pinned-folder via AX without an owner decision.
- `PinnedFolderCoverStore` must keep background enumeration and generation checks so stale async thumbnails cannot overwrite fresh covers.
- `FolderCover.isThumbnail` decides rendering: thumbnails get square-crop + border; icons render fit.
- `DirectoryWatcher.stop()` is idempotent; the fd closes only in the dispatch source cancel handler.
- The strip `.onDrop` for external files must stay on the same view level that declares the `"strip"` coordinate space, before shadow padding.
- External drop routing stays in unit-tested `StripDropRouting.route`: shelf hit -> stash, pinned-folder chip horizontal-band hit -> move into that folder, chip gaps / folder-zone tail slack -> pin, else reject.
- Only directories can pin; files dropped in chip gaps / folder-zone tail slack are a silent no-op. Re-dropping an already-pinned folder in a gap repositions it; dropping it on a folder chip moves it into that folder.
- Moving external files into a pinned folder never overwrites an existing destination. Move only when both volume identifiers are known and equal; otherwise copy through a hidden temporary item, preserve the source, and remove the temporary item on failure.
- External drop hover cleanup must not rely only on `performDrop` / `dropExited` or `folderPaths` changes. Keep `dropEntered` gating plus `.common` Timer watchdog for missing terminal callbacks and post-drop hover flicker.
- Middle-click / Force Click content-preview monitors must observe and return the original `NSEvent`. They must not consume left clicks, break folder drag, or feed planner/frontmost state.

## Shelf And Folder Popup

- Shelf stores references only, newest first. Never move/copy files implicitly. `ShelfStore.prune()` runs when opening the shelf popup.
- Shelf chip is a fixed head of the pinned-folder zone: click + drop target only, never draggable and never a `DragController` source.
- Folder and shelf share one popup panel through `PanelCoordinator.PopupContent`; preserve the one-popup-at-a-time invariant. The invariant is **desktop-wide**: exactly one popup and one drawer across all displays. Same content + same screen = close; anything else = move/switch in place (pure `SingletonPanelPlan.decide`).
- Popup lifecycle stays in `PanelCoordinator`: plain `NSView` container, pinned `NSHostingView`, alpha fade, local/global left-mouse monitors.
- `dismissFolderPopupIfOutside` must exclude the anchor chip rect with tolerance so clicking the same chip does not close-then-reopen.
- Popup closes on its **host screen's** dock target-frame change, screen-parameter change, that screen's fullscreen, or panel hide. A width change on an unrelated screen must not close it. Do not chase an animating anchor.
- Popup layout mirrors native Stacks: no header row; Finder open is the grid tail cell; drill-in uses a floating back chip.
- Popup width is derived from `FolderPopupStyle`: column count = clamp(cell count, 3, 8). It is not measured feedback.
- Grid-cell menus are hand-built via `FileItemMenuBuilder`; no Quick Look, Get Info, or rename in the nonactivating panel.
- First frame must be complete before `orderFront`: preload folder contents, warm visible icons, use synchronous `fittingSize`, and avoid first-population insertion animation.
- Switching folders while popup is open is an in-place content/frame switch, not orderOut-then-reopen.
- Popup open/close animation uses `PopoverAnimation`; taskbar/drawer layout animation stays on `DrawerAnimation`.
- Edge auto-hide is inhibited while the popup is open via `EdgeAutoHideInhibitor.folderPopupOpen`.

## Menus, Panels, And Screens

- Strip and drawer chip menus are hand-built AppKit `NSMenu`, not SwiftUI `.contextMenu`.
- No menu anywhere exposes drawer placement actions (`收进抽屉` / `移出抽屉`); stashing and unstashing are drag-only. A **not-running** drawer icon's only membership item is 从程序坞中移除 (via `AppMembershipController.removeFromDock`); a **running** drawer icon shows no membership item (owner 2026-07-12 #1 — move out by drag).
- `MenuHostNSView` claims only right-click / Control-click and returns `nil` from `hitTest` otherwise.
- Force Quit is a native alternate item after Quit, gated out for this app itself.
- `LauncherChip` menu running-state follows the passed-in `isRunning` (the displayed zone), never an independent `NSWorkspace` process query. A launch-zone icon whose process is still alive (window-closed / background) must not surface 显示/隐藏/退出. The pure decision is `LauncherMenuPlan.itemKinds` (unit-tested); `buildLauncherMenu` only renders it and queries `NSWorkspace` solely to obtain the app object for an action it already decided to show. Membership items are injected via `membershipItems` and may be multiple (e.g. a not-running kept icon shows 从程序坞中移除 and 标记为消息应用). A messaging-zone icon shows only 取消标记消息应用 — **never 在程序坞中保留** (keepInDock unmarks + converts to kept, which yanks the app out of the messaging zone; owner 2026-07-12 #2). The `appendMembershipItems` 在程序坞中保留 branch is gated `!messagingStore.contains(bid)`, and both the messaging main-window card and pop-out cards keep 取消标记消息应用.
- Finder menu items apply to both persistent Finder chip and concrete Finder windows.
- SwiftUI shadow margin is `shadowPadding = 20pt`; floating panel shadows must fit within it.
- Coordinate math on `dockFrame` / `capsuleFrame` subtracts `shadowPadding` to reach visual content, and `fittingSize.width` subtracts `2 * shadowPadding`.
- Relayout is target-frame-driven. Do not position one panel from another panel's live `.frame` during animation.
- Drawer window content must be a plain `NSView` container with the `NSHostingView` pinned inside.
- Placement panels use `NonConstrainingPanel`, not plain `NSPanel`.
- Bottom-anchored panels use `screen.frame` for bottom Y and horizontal clamp; reserve `visibleFrame` for drawer top/menu-bar height cap.
- **Per-display taskbar (owner 2026-07-27; ADR `Docs/30-per-display-taskbar.md`).** One resident bar on **every** attached display, one `ScreenBar` per `CGDirectDisplayID`. The dwell hover-switch (`commitHoverSwitch` / `handleBottomEdgeProbe`'s cross-screen branch / `hoverSwitchTimer`) is deleted — do not reintroduce it. Screen identity is `NSScreen.deviceDescription["NSScreenNumber"]` → `ScreenID`; nothing per-screen is persisted, so no display UUID is needed. "Primary" always means the menu-bar display `NSScreen.screens[0]`, **never** `NSScreen.main` (which tracks the key window — that bug shifted every Quartz conversion on mixed-height rigs and is fixed via `ScreenAttribution.quartzRect`).
- Zone nature decides placement: TOOL zones (shelf + pinned folders + drawer capsule) render on every screen with globally shared contents; APP/WINDOW chips follow their window's screen (majority-area overlap, `ScreenAttribution`); chips with no window (Finder's persistent chip, exited kept placeholders, not-running messaging apps) live on the **primary display only**. Minimized/hidden seats stick to their last known screen (`WindowEntry.screenID` + `ScreenAttribution.resolve`, session-only; the min/hidden retention branch reuses the seat verbatim — do not "helpfully" recompute it there).
- Chip order is ONE global table (`StripOrderStore` stays single) that each screen filters. **Never feed `StripOrderStore.reconciled` / `sync` / `reorder` a screen-filtered id list** — absent ids hit the 5s grace and get dropped from the global order, and `reorder` persists the truncated result to UserDefaults. Keep `partitioned()` / `liveOrderIDs` / `liveAppKeys` global and filter only in `stripEntries`, after ordering.
- `WindowRecord.screenID` / `StripItem.screenID` are current placement facts, never chip identity or persistent order keys. The `[screen]` prints (无归属 / 粘滞 / 拓扑变更 / 抖动) are permanent anomaly-path diagnostics with zero output on normal paths — same standing as `[tabfold]` / `[tabheal]`, do not remove them as 诊断遗留.
- The derived screen key belongs in `AppTracker.seatSignature`, **not** raw bounds: a screen key changes once per boundary crossing (naturally debounced), raw bounds would republish the snapshot on every poll tick during a drag. `kAXWindowMovedNotification` is deliberately NOT registered — it floods during drags and the 0.5s frontmost poll already covers the only case that matters (you must click a window to drag it).
- Fullscreen hiding is **per-screen**: a fullscreen app on display A hides only A's dock + capsule, and closes the drawer/popup only if their host screen is A. `FullscreenWindowClassifier.isFullscreen` remains the single AX predicate, gated to real `AXWindow` roles; screen bucketing lives in pure `FullscreenScreenScan`. The global `.fullscreen` visibility reason now means "every attached screen is fullscreen" and exists only to gate auto-hide arming. Edge auto-hide keeps **global** semantics (owner does not use it) — do not build per-screen auto-hide.

## Settings And Compatibility

- Do not reintroduce the multi-display strategy menu. Behavior is fixed to one resident bar per display (see **Per-Display Taskbar**).
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
- For 收尾 / 整理文档, do not expand this file by default. Update `AGENTS.md` only for new hard engineering guardrails that would prevent code regressions. Product state, roadmap, release progress, decision history, and long handoff text belong in Obsidian; historical notes belong in `Docs/Archive/`.
