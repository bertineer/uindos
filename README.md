# uindos

**Windows, on your terms.**

uindos is an opinionated, privacy-first Windows setup inspired by [Omarchy](https://omarchy.org/) and [Hyprland](https://hyprland.org/). The goal is to strip away unwanted Microsoft consumer experiences and rebuild Windows as a lean, keyboard-driven desktop—without sacrificing the ability to receive Windows security updates.

**Status: early implementation.** A Windows baseline collector and sandbox transaction engine are available. The first three per-user privacy defaults are proposed in PR #5, with dry-run as the default. PR #6 added current-user consumer AppX removal, PR #7 fixed PowerShell 7 provisioning inventory, and PR #8 proposes an expanded consumer/media app allowlist plus separate elevated deprovisioning for new users. Edge removal and the desktop are future work.

## Philosophy

- **One opinionated configuration.** This is a personal setup shared publicly, not a general-purpose Windows optimization suite.
- **Privacy by default.** Reduce unnecessary diagnostics, advertising, promotional content, account pressure, and unwanted AI integrations. Be precise about what Windows editions actually support.
- **Remove what is not needed.** Target the Edge browser, Copilot, unwanted preinstalled apps, and unnecessary background activity. Preserve dependencies required by applications, security, and servicing.
- **Build the desktop back up.** A curated tiling workflow, terminal, browser, launcher, cohesive shortcuts and visual defaults, inspired by Omarchy.
- **Keep Windows updatable and secure.** Do not disable Windows Update, Defender, UAC, BitLocker, Secure Boot, or other security protections as a routine privacy tweak.
- **Verify results.** Distinguish settings applied from settings effective; measure before/after footprint and privacy outcomes.
- **Minimal dependencies, transparent changes.** Auditable sources, explicit version pins/checksums, useful logs, and tested recovery.

See [curated consumer app removal](docs/DEBLOAT.md), [the first privacy defaults](docs/PRIVACY.md) and [the read-only baseline guide](docs/BASELINE.md) for the first diagnostic command. The [transaction-engine design](docs/TRANSACTIONS.md) describes the experimental dry-run, journaling, verification and rollback layer; it is not connected to real Windows settings yet.

The [read-only OneDrive preflight](docs/ONEDRIVE-PREFLIGHT.md) reports registered Win32 install and limited current-user signals. It does not unlink or uninstall OneDrive and cannot establish sync completion, cloud backup completeness, or file hydration.

Read [the project philosophy](docs/PHILOSOPHY.md), [architecture](docs/ARCHITECTURE.md), [decision log](docs/DECISIONS.md), and [roadmap](docs/ROADMAP.md).

## Intended workflow (not yet implemented)

1. Inspect the Windows version, edition, packages, policies, security, storage, and available recovery options.
2. Show exactly what uindos proposes to change; offer a dry run.
3. Apply reversible privacy, application-removal, and performance defaults.
4. Install and configure the curated desktop environment.
5. Validate Windows Update, security status, installed apps, and the desktop's fallback path.
6. Reconcile drift after updates only within explicitly managed settings.

## Initial software direction

| Role | Intended direction | Current decision |
| --- | --- | --- |
| Tiling/window management | [HyprWin](https://github.com/IIPikx/hyprwin), [Komorebi](https://github.com/LGUG2Z/komorebi), or [GlazeWM](https://github.com/glzr-io/glazewm) | Evaluate; no chosen dependency yet |
| Terminal | [Alacritty](https://alacritty.org/) | Preferred |
| Browser | [Ungoogled Chromium](https://ungoogled-software.github.io/ungoogled-chromium-binaries/) | Preferred, subject to secure update path |
| Shell | PowerShell 7 | Preferred |
| Launcher | A minimal keyboard-driven Windows launcher | Evaluate |
| File manager | Windows File Explorer, stripped of promotional clutter | Preferred |

**Edge removal must not implicitly remove WebView2.** Windows SmartScreen for downloaded applications is distinct from Edge browser SmartScreen and remains enabled by default.

## Scope

uindos is personal software, shared publicly for others to use or adapt. It is not an enterprise hardening baseline, a custom Windows OS image, a commercial offering, a generic package manager, or a promise of zero Microsoft traffic. Unsupported Windows component removal is treated as a compatibility risk, never a hidden default.

Development happens through small, reviewable pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).

## License

Original project content is under the [MIT License](LICENSE). Third-party software and copied material retain their own licenses. Links to external projects do not imply endorsement or inclusion.

### Taskbar visibility

Preview taskbar Search and Task View with `pwsh -NoProfile -File ./bin/uindos-taskbar.ps1`; Widgets use the separate [supported device policy command](docs/WIDGETS.md). Apply with `-Apply`, undo with `-Undo <transaction-guid>`. These commands do not reset existing pinned applications.
