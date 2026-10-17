# Roadmap

**Principle:** small PRs; do not merge untested destructive Windows changes.

| Milestone | Deliverable | Acceptance |
| --- | --- | --- |
| M0 — Foundation | Philosophy, AGENTS, architecture, decision log, roadmap | Scope and safety guardrails agreed |
| M1 — Source audit | Source-linked inventory of WinSux, Win11Debloat, WinUtil and the desktop candidates | Operations triaged by risk, edition and supported status |
| M2 — Read-only baseline | Windows 11 capability probe, installed/provisioned package inventory and baseline report | Merged PR #3; Windows 11 Pro VM baseline 05 passed 13/13 probes. See [VM acceptance](research/VM-ACCEPTANCE-2026-10-16.md). |
| M3 — Transactional core | Plan/dry-run, exact state capture, log, apply/verify, guarded undo, idempotence | Merged PRs #4/#13; Windows/Linux CI passed and VM Widgets/taskbar Apply, repeat Apply and exact-value Undo passed. Reboot/interruption recovery remains pending. |
| M4 — Privacy / debloat | Curated policy and app removals, Copilot mitigation, Edge/browser removal with WebView2 preserved | Original 19+19 removals and later Quick Assist/Get Help cleanup observed in baseline 05. PR #14 separates supported Widgets policy from taskbar preferences. Online Windows Update scan and local Search passed; other acceptance limits are in [VM evidence](research/VM-ACCEPTANCE-2026-10-16.md). Edge and broader privacy remain open. |
| M5 — Desktop | One tiler, Alacritty, private browser, shell, launcher, theme and shortcuts | Normal-user process model and reliable Explorer fallback |
| M6 — Performance | Curated measurable optimizations | No unexplained security/servicing tradeoffs; benchmark results |
| M7 — Reconciliation | Post-update drift report and scoped remediation | Update compatibility, duplicate-safe and no unexpected reinstalls |
| M8 — Hardening | Reproducible build/download supply chain, test matrix, release instructions | Publicly reviewable verification report |

## Near-term PRs

1. Repository foundation/documentation.
2. Research audit and compatibility risk matrix.
3. Read-only Windows environment and app inventory prototype, **only after** research decisions.
4. Small, separately reviewable modification modules with tests; no giant one-click destructive script.
5. Desktop prototype in VM, including testing HyprWin alternatives and browser update strategy.

## Decisions still to validate

- Tiling manager: HyprWin vs Komorebi vs GlazeWM; elevated execution and Defender exclusion are disqualifying until corrected.
- Browser update channel for Ungoogled Chromium, security release lag and package provenance.
- Windows 11 Pro constraints for policy-based telemetry controls and anti-reinstall controls.
- Edge uninstall method outside the EEA and expected compatibility with Windows upgrades.
- Search/launcher integration, exact keyboard shortcuts and a low-overhead top bar.

Community requests are evaluated for alignment with the existing vision, not for feature-count growth.

PR #9: exact Quick Assist / Get Help / Get Started app names plus per-user taskbar visibility preferences. OneDrive (Win32), Start pins and taskbar pins require distinct, carefully scoped handling.

## Next hardening work

The post-PR8 VM baseline and snapshot should precede additional destructive changes. See [Windows 11 Pro 26H2 privacy/desktop plan](research/WIN11-PRO-26H2-HARDENING.md) for the phased scope, edition restrictions, app identities, test gates, and proposed PR #11–16. Do not deploy wholesale telemetry HOSTS blocking or unsupported Edge browser uninstallation as uindos defaults.

**PR #12 — Notifications and post-update welcome.** Add a journaled, reversible per-user preference module for post-update welcome, tips and finish-setup suggestions. Pro CSP limitations and behavior verification documented; does not block initial OOBE or notifications security infrastructure.

**Next candidate — OneDrive Win32 preflight.** Read-only detection only; see [the preflight guide](ONEDRIVE-PREFLIGHT.md) and [source research](research/ONEDRIVE-PREFLIGHT.md). Unlink/uninstall remains separate and requires informed review of sync, Known Folder Move, backup, and hydration state.

**Appearance defaults candidate.** Curated dark Windows/app modes and a black
desktop are exposed through a separate [journaled appearance command](APPEARANCE.md).
Preview, exact managed-state undo, idempotence and failure/drift handling are
tested separately from native shell/UI behavior. OneDrive removal still needs
the informed data/sync review; Edge browser removal remains separate and must
preserve WebView2 and its servicing.
