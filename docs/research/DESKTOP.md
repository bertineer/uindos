# Curated desktop audit

The intended desktop is **Omarchy-inspired and Windows-native**, not a Windows-wide customizability toolkit. It runs as the current user and preserves Windows Explorer as the system shell/fallback.

## Proposed application stack

| Role | Candidate | Status | Open issue |
| --- | --- | --- | --- |
| Window tiling and workspace shortcuts | [HyprWin](https://github.com/IIPikx/hyprwin) | RESEARCH | Elevated runtime, Defender exclusion, local IPC, tray memory access, RDP |
| Alternative tilers | [Komorebi](https://github.com/LGUG2Z/komorebi), [GlazeWM](https://github.com/glzr-io/glazewm) | RESEARCH | Startup behavior, input hooks, display compatibility, license, memory/CPU |
| Terminal | [Alacritty](https://alacritty.org/) | ADOPT (pending packaging check) | Default PowerShell 7 profile, configuration and pinned supply chain |
| Browser | [Ungoogled Chromium](https://ungoogled-software.github.io/ungoogled-chromium-binaries/) | ADOPT conceptually; installation BLOCKED pending review | Third-party binary provenance, update lag and automatic security patch delivery |
| Shell | PowerShell 7 | ADOPT | Pin compatible version and select user-level default in Alacritty |
| Launcher | Lean keyboard-driven launcher (Flow Launcher is a candidate) | RESEARCH | Offline-first search, plugin/telemetry posture, hotkey conflicts |
| File manager | Windows File Explorer | ADOPT | Keep shell services even while hiding taskbar/Start UI |
| Theme/fonts | Single dark theme and Nerd Font | ADOPT | Accessibility, app/window compatibility and license |

## HyprWin source-specific concerns

At audited commit `9f4ed24dd574`:

1. [app.manifest](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.App/app.manifest) requests `requireAdministrator`. This should be `asInvoker` for a desktop app; verify keybinding/window-management limitations with non-elevated applications and RDP.
2. [Installer](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/publish/hyprwin-setup.iss) creates a broad Defender exclusion for its installation directory, which is incompatible with uindos. Remove that behavior if used.
3. [Autostart](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.Core/AutostartManager.cs) schedules the tiler at highest privilege. Rework for per-user least-privilege startup.
4. [Named pipe](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.Core/IpcServer.cs) uses default access controls. Inspect and explicitly restrict same-session/user clients; if running elevated this is an especially risky control channel.
5. [Known limitations](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/Hyprwin.Vault/Hyprwin/Problems_Security.md) include reading Explorer process memory to reproduce system-tray icons and lack of RDP support.
6. [Default keybinds](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.Core/Configuration/DefaultConfig.cs) assign `Super+Space` to layout changes, while uindos expects the launcher there; resolve key conflicts.
7. Review upstream **license file and binary provenance** before copying source; a README license claim alone should not be treated as complete redistribution diligence.

**Decision gate:** choose one tiler only after evaluating security/runtime privilege, multi-monitor behavior, fullscreen games, RDP, startup/fallback and CPU/RAM. Do not patch all tilers or develop a new window manager prematurely.

## Opinionated initial shortcut direction (not final)

| Keys | Target |
| --- | --- |
| Super + Enter | Alacritty |
| Super + Shift + Enter | Browser |
| Super + Space | Application launcher |
| Super + 1…9 | Workspaces |
| Super + Shift + 1…9 | Move focused window to workspace |
| Super + arrows | Focus |
| Super + Shift + arrows | Move or swap |
| Super + F / T / Q | Fullscreen / float / close |

Review conflicts with Windows secure shortcuts, accessibility, keyboard layouts and games. Reserve a clear normal-Explorer recovery path.

## Browser security requirements

- Use one audited distribution channel and documented publisher; do not embed a random current unsigned binary.
- Verify signatures/checksums and expected build versions where available, and monitor Chromium security advisories/update latency.
- Define patch response and fail safely on outdated browser builds. Ungoogled Chromium's browser process does not solve OS-wide telemetry by itself.
- Keep Windows SmartScreen for downloaded executables independent of Microsoft Edge browser removal.

## Do not conflate daily UX with privileged system maintenance

Desktop processes should use standard user integrity; only setup/maintenance actions that require admin rights should request elevation temporarily. No permanent SYSTEM helpers, broad Defender exclusions, shell replacements or keyboard bypasses by default.
