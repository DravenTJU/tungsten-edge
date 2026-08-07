# Docs

This directory is not the live project status source.

- Current progress and backlog: the board `进度看板.html` in the owner's Obsidian vault (single file; content in its `#board-data` JSON block).
- Engineering guardrails for agents: `../AGENTS.md`.
- **Product decisions and their rationale: `27-product-decisions.md` (here, not the vault** — moved 2026-08-01).
- Active repo-local references kept here:
  - `project-structure.md` — codebase tour for new contributors, plus build / local signing certificate / test-running instructions.
  - `05-known-platform-quirks.md` — platform behavior that still affects implementation.
  - `22-window-focus-flicker-debugging.md` — focus / activation debug history and hard-won constraints.
  - `23-rollback-ledger.md` — executable rollback ledger (revert commands + verification state); visual counterpart is the mainline timeline in the owner's Obsidian board `进度看板.html`.
  - `26-idle-performance-polling.md` — the three idle background polls: verified constraints plus the reviewed-and-corrected throttling designs. A design archive, **not** a backlog — the throttling was rejected by the owner.
  - `27-product-decisions.md` — why each product decision was made and when it may be revisited. `AGENTS.md` states the constraint; this states the reasoning and the reversal history. Agents update it directly.
  - `28-process-pitfalls.md` — pitfalls in *how we work* (branching, packaging, acceptance, versions), not in the code. Read before a release, a performance comparison, or an acceptance pass.
  - `30-per-display-taskbar.md` — ADR for the one-resident-bar-per-display change (owner decisions + why each mechanism is built the way it is).
  - `31-per-display-taskbar-verification.md` — the same change's build / run / acceptance checklist and `[screen]` diagnostics reference.

Everything else is historical and lives under `Archive/`:

- `Archive/Planning/` — early architecture plans, old acceptance notes, frozen progress boards, old known issues.
- `Archive/Samples/` — real-window sample findings.
- `Archive/Engineering/` — engineering deep dives referenced from `AGENTS.md`.
- `Archive/Releases/` — release notes.

Do not treat archived notes as current state. Use them only as evidence or historical context.
