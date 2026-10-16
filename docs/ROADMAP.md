# Roadmap

**Principle:** small PRs; do not merge untested destructive Windows changes.

| Milestone | Deliverable | Acceptance |
| --- | --- | --- |
| M0 — Foundation | Philosophy, AGENTS, architecture, decision log, roadmap | Scope and safety guardrails agreed |
| M1 — Source audit | Source-linked inventory of WinSux, Win11Debloat, WinUtil and the desktop candidates | Operations triaged by risk, edition and supported status |
| M2 — Read-only baseline | Windows 11 capability probe, installed/provisioned package inventory and baseline report | Implemented in merged PR #3; Windows-hosted runner CI passed; dedicated Windows 11 Pro VM validation pending |
| M3 — Transactional core | Plan/dry-run, exact state capture, log, apply/verify, guarded undo, idempotence | Merged PR #4, sandbox CI passed; dedicated Windows 11 Pro VM validation pending |
| M4 — Privacy / debloat | Curated policy and app removals, Copilot mitigation, Edge/browser removal with WebView2 preserved | PR #8 successfully removed 19 current-user and 19 provisioned apps in the VM; independent after-state and servicing checks pending. PR #9 merged residual app allowlist and taskbar visibility. Extended privacy/desktop hardening in [26H2 plan](research/WIN11-PRO-26H2-HARDENING.md). |
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
