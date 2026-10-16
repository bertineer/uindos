# Architecture decision record (ADR)

## Accepted — 2026-10-16

**ADR-001: uindos is opinionated, not a toolkit.** One preferred configuration; users can fork or modify files. No profile marketplace or broad tweak UI.

**ADR-002: Privacy and security coexist.** Reduce advertising, AI integration, consumer features and diagnostics wherever effective. Never silently disable Windows security controls to achieve it.

**ADR-003: Windows Update is essential.** All defaults must preserve security and cumulative updates and repair/servicing paths.

**ADR-004: Two-phase user experience.** First remove unwanted Windows components; then apply a minimal, Hyprland/Omarchy-inspired desktop.

**ADR-005: Edge browser removal is a requirement, not WebView2 removal.** Retain Windows SmartScreen's application reputation checks by default and explicitly document unsupported Edge-uninstall paths.

**ADR-006: No permanent elevated desktop.** Routine desktop processes must run without administrator privilege. Defender exclusions for the desktop's install directory are unacceptable.

**ADR-007: Evidence before claims.** A set policy is not necessarily an effective policy; measure privacy/performance when feasible and report unsupported outcomes.

**ADR-008: Public personal open source.** No commercial requirements, enterprise support promise or perpetual compatibility burden.

## Under evaluation

- **ADR-TBD-009:** tiler selection and whether HyprWin should be patched upstream or replaced.
- **ADR-TBD-010:** Ungoogled Chromium trusted distribution and update verification.
- **ADR-TBD-011:** per-edition supported mechanisms for removing/blocking Copilot and other apps.
- **ADR-TBD-012:** minimal scheduled reconciliation vs event-triggered checks.
- **ADR-TBD-013:** safe unsupported Edge removal and rollback.

Update this file when a proposal has been researched and tested; do not silently promote a proposal to an accepted requirement.

**ADR-014: Privacy v1 is deliberately per-user and narrowly allowlisted (PR #5).** On Windows 11 Pro/Pro N, initially apply user-tailored-experiences and third-party suggestions Group Policy values, plus the per-user advertising-ID preference as best-effort. Do not claim machine-wide policy enforcement, diagnostic-data-off, or that personalized ads are completely removed. Keep these changes undoable and independent of Windows Update, Defender and Edge removal.

**ADR-015: Curated AppX removal is not a reversible registry action (PR #6).** The first consumer-app stage handles only five exact Microsoft-signed package identities in the current Windows 11 Pro user context. Preview is read-only; uninstall requires two explicit switches, logs exact package identity and partial outcomes, and has no automatic rollback or user-data recovery promise. Deprovisioning, all-user removal and post-update reinstallation prevention are separate research/test milestones. Keep Store, App Installer, Xbox, WebView2, Windows security and shared frameworks untouched.


**ADR-016: Separate scoped removal and deprovisioning (PR #8).** The fixed consumer/media allowlist expands to 21 names while preserving codecs, Media Foundation, Store/WinGet, gaming, security and WebView2. Existing-user AppX removal remains current-user-only with explicit data-loss consent; new-user servicing is a separate elevated command with separate deprovisioning consent, exact identity verification, journaling and no `-AllUsers`. Neither operation has an automatic app-data rollback. Test only in a disposable Windows VM until validated.

**ADR-022: OneDrive starts with read-only preflight (candidate).** Detect only exact Microsoft OneDrive uninstall registrations and report process/account/Known Folder signals without publishing private paths or account identifiers. Files On-Demand hydration, sync health, backup completeness, and uninstall safety remain unknown/manual review. Any unlink or uninstall requires a separate design and informed user consent; never execute registry uninstall commands or delete sync folders/cloud content.


## Proposed for validation — privacy and desktop hardening (2026-10-16)

- **ADR-TBD-017:** Disable documented Widgets on Windows 11 Pro via `AllowNewsAndInterests=0`, plus lock-screen user preference. Prefer policy/Settings over removing Widgets runtime packages.
- **ADR-TBD-018:** Reversible per-user notification, post-update welcome, dark mode, Explorer and Start behavior; no unsupported Pro-only policy claims. Preserve user-selected location permission.
- **ADR-TBD-019:** Separate Win32 OneDrive uninstall with file/sync preflight, exact package provenance and explicit consent; do not delete sync folders or cloud content.
- **ADR-TBD-020:** Measure Windows 11 Pro endpoint traffic before evaluating any optional HOSTS/DNS blocking. Never block servicing/security/identity endpoints, and never claim zero telemetry without evidence.
- **ADR-TBD-021:** Treat Bing Search package and old-style context menu as regression-gated experiments; keep local Search and Explorer functionality intact. See [research plan](research/WIN11-PRO-26H2-HARDENING.md).
