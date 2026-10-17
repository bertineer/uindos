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

The [2026-10-17 client-removal validation](research/CLIENT-UNINSTALL-2026-10-17.md)
records successful current-user OneDrive client removal, retained local
folders/recovery installers, and an Edge force-uninstall attempt refused by
the native installer with exit93. Edge remains installed; WebView2/updater
component checks passed. Neither result establishes controlled-idle RAM or
complete privacy acceptance. A generic destructive removal command remains
out of scope for this evidence update.

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

**Search suggestions candidate.** A [single journaled user policy](SEARCH-SUGGESTIONS.md)
has passed VM Apply/repeat/Undo and Start/web-versus-local Search observations
after a manual Search flyout refresh. Reboot persistence remains pending. Pins,
package removals, indexing replacements and service tuning remain separate.

**Start pins preflight candidate.** [Read-only export and registration checks](START-PINS-PREFLIGHT.md)
separate pinned WhatsApp/LinkedIn entries from installed packages. Current pin
state and reset/restore limitations must be reviewed before layout changes.
Taskbar cleanup needs separate handling for user-created pins.

**Start policy prerequisite.** The transaction core can now capture and restore
literal `REG_EXPAND_SZ` data without expanding environment variables. Isolated
registry Apply/repeat/Undo and affected module regressions passed. This enables
the correct type for Start policy JSON.

**Start reset candidate.** The [one-time reset command](START-RESET.md) implements
preview, explicitly acknowledged Apply and policy-only Undo with a fresh private
layout backup and conservative authority checks. Mocked transactions and native
normal/elevated read-only previews pass. On Pro x64 26300.9711, live elevated
Apply as the same Explorer user/session and same-operation repeat passed; exact
registry kinds/data were read back and both journal steps were applied. The
same-session Start Pinned surface was empty, All apps remained visible, and
local Start and Explorer filename search worked. Later sign-in persistence,
live policy Undo and subsequent pin customization remain pending. Exact
original-layout reconstruction is not promised for absent-package pins.

**Privacy policy writer corrected.** The existing three-value
[privacy command](PRIVACY.md) keeps normal-user preview but requires temporary
elevation as the same Explorer user/session for Apply/Undo, with an optional
absolute persistent journal directory. Native Apply, unchanged repeat, exact
prior-absence Undo and final reapply passed on Pro x64 26300.9711. The existing
advertising-ID preference stayed unchanged. Effective Windows behavior and
later sign-in persistence remain separate acceptance work.

**Baseline optimization phase.** Target less than 2 GB used physical memory at
controlled idle, with security, servicing and core functionality retained.
No new software except Git/GitHub CLI until this baseline is optimized;
PowerToys, Everything and other desktop provisioning remain deferred. Current
active-session sampling exceeds the target and is not an idle benchmark.
Use repeated physical-memory and CPU samples under the same conditions;
never sum shared working sets or subtract assumed tooling overhead.

**Edge background policies.** A [separate preview-first command](EDGE-BACKGROUND.md)
manages only Startup Boost and browser background mode. Native two-policy
Apply, unchanged repeat, exact prior-absence Undo and final reapply passed on
Edge Stable 155 / Pro x64 26300.9711. Normal-user mutation guards passed;
Defender AV/realtime/tamper remained enabled. Browser process exit, sign-in
persistence and controlled-idle RAM benefit remain separate acceptance gates.
No service-disable bundle, package deletion or replacement software is included.

**Cross-device continuation policy.** The [single-value command](SHARED-EXPERIENCES.md)
sets EnableCdp DWORD0 with authority guards and exact-state Undo. This privacy
choice also prevents Windows settings backup. Reboot/paired-device acceptance
and controlled-idle memory remain separate gates; no CDP service is disabled.
