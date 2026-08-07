# Docs

This directory is not the live project status source.

- Current product state, roadmap, and decisions: owner's Obsidian vault, entry `00 macos-dock-cc-v2 总览.md`.
- Engineering guardrails for agents: `../AGENTS.md`.
- Active repo-local references kept here:
  - `project-structure.md` — codebase tour for new contributors, plus build / local signing certificate / test-running instructions.
  - `05-known-platform-quirks.md` — platform behavior that still affects implementation.
  - `22-window-focus-flicker-debugging.md` — focus / activation debug history and hard-won constraints.
  - `23-per-display-taskbar.md` — ADR for the one-resident-bar-per-display change (owner decisions + why each mechanism is built the way it is).
  - `24-per-display-taskbar-verification.md` — the same change's build / run / acceptance checklist and `[screen]` diagnostics reference.

Everything else is historical and lives under `Archive/`:

- `Archive/Planning/` — early architecture plans, old acceptance notes, frozen progress boards, old known issues.
- `Archive/Samples/` — real-window sample findings.
- `Archive/Engineering/` — engineering deep dives referenced from `AGENTS.md`.
- `Archive/Releases/` — release notes.

Do not treat archived notes as current state. Use them only as evidence or historical context.
