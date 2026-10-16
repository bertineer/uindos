# Proposed architecture (design, not implemented)

**Status:** initial architecture proposal; decisions require research and Windows VM validation.

## Phases

1. **Inspect / plan:** determine Windows edition, build, architecture, activation, BitLocker/recovery state, device type, installed/provisioned AppX, Win32 programs, policies and update status. Print a no-write plan.
2. **Foundation:** exact-state backups, supported policy changes, curated app deprovisioning, Edge removal workflow and selected performance changes. Each change is gated by build/edition and verified.
3. **Desktop:** choose one proven tiling manager, terminal, private browser, launcher, fonts, shortcuts and a lean taskbar replacement; retain Windows Explorer shell and escape hatch.
4. **Validate:** compare package inventory, security/update health, footprint and optional traffic observations. Report each change as verified, ineffective, unsupported, failed or pending reboot.
5. **Reconcile:** lightweight user-consented scheduled checks after relevant updates/sign-in, limited to managed settings. No constantly running privileged service.

## Logical components

```text
uindos/
  config/           # One curated default manifest + pinned artifact provenance
  src/core/         # Detect, plan, apply, verify, backup, undo
  src/foundation/   # Privacy, app removal, Edge, servicing, performance
  src/desktop/      # Curated packages, tiler config, keybinds, theme
  src/maintenance/  # Scoped drift detection and reconciliation
  tests/            # Unit checks and Windows VM/upgrade matrix
  docs/research/    # Source-specific evidence and risk analysis
```

These directories are planned, not a commitment to create unnecessary abstraction.

## Change contract

Each internally curated action should state:

- stable ID and rationale;
- source policy/API/documentation and Windows edition/build range;
- current-state detector and prerequisites;
- proposed changes and risk classification;
- apply/verify/rollback procedures (or explicit irreversible state);
- security, update and compatibility impacts;
- measurements and reproducible test cases.

The execution engine captures the *actual* previous state rather than resetting every value to an assumed default. Actions are idempotent and report `planned`, `applied`, `verified`, `skipped`, `unsupported`, `failed` or `requires-reboot`.

## Windows concerns

- **Diagnostic data:** an `AllowTelemetry` registry value is not proof of effective disablement. On Pro, diagnostic-data-off is unsupported; report the minimum that actually applies.
- **AppX:** distinguish installed users, provisioned packages for new accounts, WinGet/Win32 packages, and multiple Copilot distribution channels.
- **Edge:** distinguish Edge browser from WebView2, browser updates from other app servicing, and supported from unsupported uninstall paths.
- **Windows Update:** keep BITS, update services, scheduled tasks, component store, servicing stack and recovery operable.
- **Application control:** where AppLocker is considered, validate the precise OS build/edition and audit mode first; never deploy a default-deny policy without testing all system apps.
- **HyprWin:** current upstream binary requests elevation and its installer adds a Defender exclusion; not eligible as-is for default install. Evaluate alternative tilers or a security-reviewed fix upstream/fork.
- **Ungoogled Chromium:** release provenance and prompt security updates are prerequisites to selection.

## Trust model

Runtime downloads, if needed, are version-pinned with SHA-256 verification; preferably use an official package-manager manifest and validate the installed version. No `iex` of downloaded source. Admin privileges are temporary and isolated from daily desktop apps. Any IPC endpoints are per-user and authenticated/ACL restricted.

## Compatibility and test baseline

First target: Windows 11 Pro x64 on clean install and existing install in disposable VMs, with an upgrade/regression path; extend to Home/Enterprise only after tested. Verify disk encryption, Windows Update, Defender, Store dependency behavior, WSL, gaming, RDP, multi-monitor and app installs according to relevance.

See [ROADMAP.md](ROADMAP.md) for incremental PR boundaries.
