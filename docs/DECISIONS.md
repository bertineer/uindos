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
