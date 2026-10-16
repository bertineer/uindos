# AGENTS.md — uindos

This file is the working contract for AI coding agents and contributors in this repository.

## Product intent

uindos is a personal, public, **opinionated** Windows setup inspired by Omarchy/Hyprland. It has one coherent default configuration: remove unwanted Microsoft consumer features, minimize privacy exposure and background overhead, then provide a fast keyboard-driven desktop. It is **not** WinUtil, a tweak marketplace, or a universal Windows-support product.

## Non-negotiable constraints

1. **Do not break Windows servicing.** Keep Windows Update, cumulative/security updates, component repair and Microsoft Defender definition updates functional. Never disable BITS, wuauserv, UsoSvc, WaaSMedicSvc, or update scheduled tasks wholesale as a default.
2. **Do not weaken security to claim privacy.** No default disabling of Defender, tamper protection, UAC, Windows SmartScreen, BitLocker, Secure Boot, memory integrity, certificate checks, or exploit protections. Distinguish Edge browser SmartScreen from Windows reputation-based protection.
3. **Do not execute remote mutable scripts.** No `irm | iex`, `iwr | iex`, or equivalent at runtime. Download pinned artifacts only from authenticated sources, validate hashes/signatures where available, and record provenance.
4. **Do not require elevation for the desktop session.** Elevation is only for narrowly scoped system modifications. The tiling manager, status bar, browser, terminal and launcher must operate as the normal user. No global Defender exclusion.
5. **Do not pretend unsupported policy values work.** Document Windows edition/build requirements; separate desired state, effective state and observable outcome. A registry value of `AllowTelemetry=0` on Windows Pro is *not* proof of diagnostic-data-off.
6. **Never hard-delete OS internals.** Use documented package/feature servicing when possible, preserve WebView2 and servicing dependencies, and never delete arbitrary component-store folders, protected services, other users' startup entries or third-party scheduled tasks en masse.
7. **Be reversible where feasible.** Snapshot exact prior state before changing it. System Restore is a supplement, not a universal rollback mechanism. Where irreversible, identify that explicitly and require informed acknowledgment.
8. **Default to idempotence, dry-run, and transparency.** Running uindos twice must not accumulate changes or misreport success. An error cannot silently count as a success.
9. **Measure the benefit and cost.** No cargo-cult performance tweaks; collect pre/post evidence and regression tests for security, update health, memory, disk, game performance and battery, as applicable.
10. **Respect upstream rights.** Inventory origin, source commit, license, attribution, and any bundled artifacts. Do not copy code from uncertain-license repositories.

## Architecture / style

- PowerShell 7 for orchestration where practical; Windows PowerShell 5.1 only when required for supported Windows servicing APIs.
- Avoid installers, services, permanent elevation, GUIs, external runtimes and dependencies unless justified.
- A single curated default manifest; internal flags are for compatibility/testing, not user-facing preset explosion.
- Split foundation/debloat/privacy from desktop provisioning and post-update reconciliation.
- Explicit Windows version/edition gating; Windows 11 is the initial target, primarily Pro, with separately documented capabilities for other editions.
- Keep changes small, cohesive, and reviewable. Prefer functions that can report `Detect`, `Plan`, `Apply`, `Verify` and `Undo` outcomes.

## Required work sequence

1. Read README, docs/PHILOSOPHY.md, docs/ARCHITECTURE.md, docs/DECISIONS.md, and docs/ROADMAP.md.
2. For Windows-specific behavior, inspect official Microsoft documentation and source code at pinned revisions before proposing an implementation. Write source links and applicability notes in docs/research/.
3. State expected benefit, risks, prerequisites, conflict with current Windows build/edition, rollback and tests.
4. Build the smallest implementation that serves the project's opinionated default.
5. Add tests or test instructions and demonstrate read-only detection before any destructive changes.
6. Report what actually passed and what still requires on-device verification. Never claim Windows behavior was tested when it was not.
7. Open a targeted PR; do not directly alter `main`.

## Forbidden shortcuts

- No Safe Mode automation, TrustedInstaller impersonation, EFI/BCD changes, arbitrary SYSTEM service-path modification, or AV evasion to bypass protections without an independently reviewed exceptional design.
- No blanket disabling of IPv6, update services, device encryption, firewall, recovery, SmartScreen or driver signature enforcement.
- No silent removal of user-installed programs or deletion of user profiles/data.
- No persistent browser with unknown update provenance or unverified unsigned binaries.
- No privacy guarantees unsupported by measured results or Microsoft policy availability.

## PR checklist

- [ ] Intent and affected Windows editions/builds documented
- [ ] Source/policy provenance and supported status recorded
- [ ] Dry-run and detection path included
- [ ] Exact state backup, rollback or explicit irreversibility documented
- [ ] Security and Windows Update regression risks assessed
- [ ] Successful/failed/unsupported/skipped outcomes differentiated
- [ ] No elevated desktop processes or broad Defender exclusions
- [ ] Tests included, or exact manual Windows VM test plan provided
- [ ] README/roadmap/decision log updated as needed
