# Architecture decision record (ADR)

## Accepted — 2026-10-16

**ADR-026: Target a fresh Windows 11 Pro installation.** uindos is designed
to build an opinionated baseline from a fresh Windows 11 Pro installation,
before personal files, cloud-sync accounts, daily-use applications and desktop
customization are introduced. It is not a general cleanup tool for an existing
daily-use installation. A fresh installation is a prerequisite, not evidence
that local files are disposable or that every operation is reversible.

The future combined entry point must prominently warn about this intended
starting state before modifications, disclose application removal, settings
and layout resets, and potential data-loss boundaries. Keep preview available
and preserve per-operation safety/consent checks; a global
warning does not replace them. The combined runner and warning are planned,
not implemented by this documentation change.

**ADR-001: uindos is opinionated, not a toolkit.** One preferred configuration; users can fork or modify files. No profile marketplace or broad tweak UI.

**ADR-002: Privacy and security coexist.** Reduce advertising, AI integration, consumer features and diagnostics wherever effective. Never silently disable Windows security controls to achieve it.

**ADR-003: Windows Update is essential.** All defaults must preserve security and cumulative updates and repair/servicing paths.

**ADR-004: Two-phase user experience.** First remove unwanted Windows components; then apply a minimal, Hyprland/Omarchy-inspired desktop.

**ADR-005: Edge browser removal is a requirement, not WebView2 removal.** Retain Windows SmartScreen's application reputation checks by default and explicitly document unsupported Edge-uninstall paths.

**ADR-006: No permanent elevated desktop.** Routine desktop processes must run without administrator privilege. Defender exclusions for the desktop's install directory are unacceptable.

**ADR-007: Evidence before claims.** A set policy is not necessarily an effective policy; measure privacy/performance when feasible and report unsupported outcomes.

**ADR-008: Public personal open source.** No commercial requirements, enterprise support promise or perpetual compatibility burden.

## Under evaluation

**ADR-025: Disable optional Edge browser background residency with policy.**
Use exactly `StartupBoostEnabled=0` and `BackgroundModeEnabled=0` under the
mandatory machine Edge policy key, with preview, installed-version gating,
exact-state journals and guarded Undo. Preserve browser launch, WebView2,
Edge Update and SmartScreen. Measure effective process behavior and physical
memory separately from registry readback. No memory target justifies weakening
security or emptying process working sets. See [guide](EDGE-BACKGROUND.md).

- **ADR-TBD-009:** tiler selection and whether HyprWin should be patched upstream or replaced.
- **ADR-TBD-010:** Ungoogled Chromium trusted distribution and update verification.
- **ADR-TBD-011:** per-edition supported mechanisms for removing/blocking Copilot and other apps.
- **ADR-TBD-012:** minimal scheduled reconciliation vs event-triggered checks.
- **ADR-TBD-013:** safe unsupported Edge removal and rollback.

Update this file when a proposal has been researched and tested; do not silently promote a proposal to an accepted requirement.

**ADR-024: One reversible user search-suggestions policy.** Set only the Pro
`DisableSearchBoxSuggestions` policy through a preview-first command with exact
state journals. Its documented contract concerns File Explorer search history;
Start web-result suppression was observed on build 26300.9711 after manually
refreshing the current user's Search flyout, and remains a tested build-specific
outcome. The policy writer requires temporary elevation for the same Explorer
user/session; ordinary desktop processes stay non-elevated. Preserve local
Search, indexing and Explorer. Do not add unsupported Pro web-results policies
or restart processes automatically. See [research](research/SEARCH-SUGGESTIONS.md).

**ADR-014: Privacy v1 is deliberately per-user and narrowly allowlisted (PR #5).** On Windows 11 Pro/Pro N, initially apply user-tailored-experiences and third-party suggestions Group Policy values, plus the per-user advertising-ID preference as best-effort. Do not claim machine-wide policy enforcement, diagnostic-data-off, or that personalized ads are completely removed. Keep these changes undoable and independent of Windows Update, Defender and Edge removal.

**ADR-015: Curated AppX removal is not a reversible registry action (PR #6).** The first consumer-app stage handles only five exact Microsoft-signed package identities in the current Windows 11 Pro user context. Preview is read-only; uninstall requires two explicit switches, logs exact package identity and partial outcomes, and has no automatic rollback or user-data recovery promise. Deprovisioning, all-user removal and post-update reinstallation prevention are separate research/test milestones. Keep Store, App Installer, Xbox, WebView2, Windows security and shared frameworks untouched.


**ADR-016: Separate scoped removal and deprovisioning (PR #8).** The fixed consumer/media allowlist expands to 21 names while preserving codecs, Media Foundation, Store/WinGet, gaming, security and WebView2. Existing-user AppX removal remains current-user-only with explicit data-loss consent; new-user servicing is a separate elevated command with separate deprovisioning consent, exact identity verification, journaling and no `-AllUsers`. Neither operation has an automatic app-data rollback. Test only in a disposable Windows VM until validated.

**ADR-022: OneDrive starts with read-only preflight (candidate).** Detect only exact Microsoft OneDrive uninstall registrations and report process/account/Known Folder signals without publishing private paths or account identifiers. Files On-Demand hydration, sync health, backup completeness, and uninstall safety remain unknown/manual review. Any unlink or uninstall requires a separate design and informed user consent; never execute registry uninstall commands or delete sync folders/cloud content.


## Proposed for validation — privacy and desktop hardening (2026-10-16)

**ADR-024: Start reset and policy Undo have different recovery boundaries.**
Use only the documented Configure Start Pins user policy, with an empty
apply-once payload stored as the ADMX-defined REG_EXPAND_SZ and enabled last.
Default to read-only preview, refuse existing/uncertain management authority,
capture fresh private exports and exact policy prior state, and require informed
layout-loss acknowledgment. UndoPolicy restores the two owned policy values;
an export cannot promise exact original pins, especially for absent apps. Keep
sign-in coordination and actual layout acceptance separate from registry
verification. See [workflow](START-RESET.md) and [sources](research/START-RESET.md).

**ADR-023: One curated per-user appearance.** Dark Windows/app color modes and
a black desktop use the existing journaled engine with separate fixed targets.
The desktop API preserves wallpaper/slideshow sources for undo; per-monitor
image visibility is checked without confusing slideshow flags with background
enable state. Default preview is read-only, changes run as the Explorer user,
and no image download, package deletion or permanent helper is introduced.
See [source applicability](research/APPEARANCE-DEFAULTS.md) and
[behavior/recovery](APPEARANCE.md); on-device and reboot acceptance remain
separate from mocked tests.

- **ADR-TBD-017:** Disable documented Widgets on Windows 11 Pro via `AllowNewsAndInterests=0`, plus lock-screen user preference. Prefer policy/Settings over removing Widgets runtime packages.
- **ADR-TBD-018:** Reversible per-user notification, post-update welcome, dark mode, Explorer and Start behavior; no unsupported Pro-only policy claims. Preserve user-selected location permission.
- **ADR-TBD-019:** Separate Win32 OneDrive uninstall with file/sync preflight, exact package provenance and explicit consent; do not delete sync folders or cloud content.
- **ADR-TBD-020:** Measure Windows 11 Pro endpoint traffic before evaluating any optional HOSTS/DNS blocking. Never block servicing/security/identity endpoints, and never claim zero telemetry without evidence.
- **ADR-TBD-021:** Treat Bing Search package and old-style context menu as regression-gated experiments; keep local Search and Explorer functionality intact. See [research plan](research/WIN11-PRO-26H2-HARDENING.md).
