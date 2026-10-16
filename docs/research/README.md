# uindos — source research and triage

**First-pass source audit: 2026-10-16. Documentation only; no changes have been tested on Windows.**

This directory inventories the useful and risky approaches found in WinSux, Win11Debloat, WinUtil and HyprWin. Its purpose is to guide uindos's **single opinionated Windows setup**, not to produce a public tweak catalog.

- [SOURCES.md](SOURCES.md) — commit-pinned code and Microsoft documentation.
- [OPERATIONS.md](OPERATIONS.md) — proposed dispositions for privacy, debloat, update, security and performance operations.
- [DESKTOP.md](DESKTOP.md) — tiling desktop, browser and terminal decisions still under evaluation.
- [VALIDATION.md](VALIDATION.md) — prerequisite Windows VM, update and measurement protocol.

## Disposition vocabulary

- **ADOPT:** useful requirement or supported method; **not yet implemented**.
- **ADAPT:** keep the purpose but change the implementation, scope or default.
- **RESEARCH:** needs policy/edition support check and Windows testing before decision.
- **REJECT:** violates uindos's default security, reliability or privacy principles.
- **OUT OF SCOPE:** not needed for this project.

Source inspection shows what code *attempts*. It does **not** prove effective settings, real telemetry reduction, compatibility, actual file-space savings or performance improvement. A policy key present on Windows Pro is not proof the edition honors it.

## Findings

1. **WinSux:** valuable list of customization targets but its elevated multi-reboot, driver wipe, Defender modifications, mass scheduled-task removal and BitLocker decryption make it unsuitable as an installer.
2. **Win11Debloat:** mature feature catalog, selected-app classification, registry snapshots, undo and user-profile/app-provisioning mechanisms worth studying. It still cannot override Microsoft's policy support boundaries.
3. **WinUtil:** useful preset/automation and MicroWin image-customization patterns. Its MicroWin post-install code disables Windows Update services and substitutes a localhost WSUS server; that path cannot be reused.
4. **HyprWin:** compelling Hyprland-like UX, but currently requests permanent administrator privilege, uses elevated scheduled autostart, adds a Defender exclusion and has documented tray/RDP limitations. Requires security redesign or a different tiler.
5. **Browser:** Ungoogled Chromium fits the desired privacy experience, but third-party build provenance and timely security updates must be verified before automatic installation.

## Implementation acceptance gate

Before converting any candidate to code, document: exact Windows edition/build support; source and license provenance; detect/plan/apply/verify/undo operations; backup semantics; security/update implications; read-only dry run; Windows VM results; and observable improvement where the claim is empirical.
