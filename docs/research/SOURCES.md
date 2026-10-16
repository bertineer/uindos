# Pinned audit references

Snapshot date: **2026-10-16**. SHA identifies examined source code, not an approved runtime dependency or verified release binary.

| Source | Commit | Role |
| --- | --- | --- |
| [bertineer/winzep](https://github.com/bertineer/winzep) | [`91adbfd63b7e`](https://github.com/bertineer/winzep/commit/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573) | Existing user's fork of WinSux |
| [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) | [`25c3999be54e`](https://github.com/Raphire/Win11Debloat/commit/25c3999be54e358bb7343a72223e4b1110e64e61) | Feature/registry/app-removal patterns |
| [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) | [`07ccd8e2e755`](https://github.com/ChrisTitusTech/winutil/commit/07ccd8e2e755a706f31569808b31f5b77acad6a9) | Automation, app removals and MicroWin |
| [IIPikx/hyprwin](https://github.com/IIPikx/hyprwin) | [`9f4ed24dd574`](https://github.com/IIPikx/hyprwin/commit/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee) | Windows tiling/window management candidate |

## WinSux source

- [Bootstrap and downloaded executables](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/winsux.ps1), including Safe Mode/RunOnce and unverified live downloads.
- [Safe Mode protected settings and driver cleanup](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/stepone.ps1).
- [Normal mode customization](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1), including Edge, AppX, optional features, startup/tasks, BitLocker, performance and Windows Update manipulations.
- [Registry payload](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/reg.reg); [timer service C#](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/settimerresolutionservice.cs). These were inventoried at a high level, not fully exhaustively analyzed.

## Win11Debloat source

- [Features manifest](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/Features.json); [default selection](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/DefaultSettings.json); [app catalog](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/Apps.json).
- [AppX/WinGet removal](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Scripts/AppRemoval/Remove-SelectedApps.ps1) (see all-users and provisioning path).
- [Apply/undo orchestration](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Scripts/Features/Invoke-Changes.ps1); [exact registry backup planning](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Scripts/Features/Backup-RegistrySnapshotCapture.ps1).
- [Telemetry settings](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Regfiles/Disable_Telemetry.reg); [scheduled-task actions](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Scripts/Features/Telemetry-ScheduledTasks.ps1).
- The snapshot contains **104 feature entries** and **139 application entries** in its catalogs. These are inventory sizes, **not** proof of 104 effective or safe tweaks.

## WinUtil source

- [Preset manifest](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/config/preset.json); [tweaks manifest](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/config/tweaks.json); [AppX catalog](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/config/appx.json).
- [Provisioned AppX removal](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/functions/private/Remove-WinUtilProvisionedAPPX.ps1).
- [MicroWin image customization script](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/functions/private/Invoke-WinUtilISOScript.ps1#L494-L650) including disabling BITS, wuauserv, UsoSvc, WaaSMedicSvc and update tasks, and directing WSUS to localhost:8080.
- [Windows Update repair script](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/functions/public/Invoke-WPFFixesUpdate.ps1#L123-L155) contains broad registry-policy deletion; do not borrow blindly.

## HyprWin source

- [Features and documented keybindings](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/README.md); [default TOML](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.Core/Configuration/DefaultConfig.cs).
- [Application manifest](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.App/app.manifest) declares `requireAdministrator`.
- [Installer](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/publish/hyprwin-setup.iss) adds a Windows Defender installation-directory exclusion.
- [Autostart](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.Core/AutostartManager.cs) creates a highest-privilege logon task.
- [Local named-pipe IPC](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.Core/IpcServer.cs) uses the default pipe security descriptor; [command handler](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/src/HyprWin.App/App.xaml.cs) supports window operations. Threat-model local callers before shipping.
- [Known limitations and security notes](https://github.com/IIPikx/hyprwin/blob/9f4ed24dd57454d2c3c2083c0539c9a82ffddeee/Hyprwin.Vault/Hyprwin/Problems_Security.md) include raw reads of Explorer's tray memory, RDP incompatibility and UWP/window-focus issues.

## Microsoft documentation: applicability matters

- [Diagnostic data by edition](https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization) — `Diagnostic data off` is documented for Enterprise, Education and Server, not standard Pro.
- [Required service data](https://learn.microsoft.com/en-us/windows/privacy/required-service-data) — turning off optional diagnostics does not eliminate every service-related connection.
- [Manage OS component connections](https://learn.microsoft.com/en-us/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services) — guidance may be specific to managed/Enterprise devices.
- [Experience CSP: consumer features](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience) — `AllowWindowsConsumerFeatures` does **not** support Windows Pro.
- [WindowsAI policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai) — deprecated `TurnOffWindowsCopilot` does not cover the new Copilot experience; policy effects depend on build and edition.
- [WebView2 Evergreen vs Fixed runtime](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/evergreen-vs-fixed-version) — WebView2 is not the Edge browser and must remain serviced.

## Other candidates

- [Ungoogled Chromium Windows binaries](https://ungoogled-software.github.io/ungoogled-chromium-binaries/), [Windows packaging repo](https://github.com/ungoogled-software/ungoogled-chromium-windows).
- [Komorebi](https://github.com/LGUG2Z/komorebi), [GlazeWM](https://github.com/glzr-io/glazewm), [Alacritty](https://alacritty.org/) and [Omarchy](https://omarchy.org/).

**Limits:** no downloaded WinSux executables were reverse-engineered or verified; no Windows VM tests, network captures, antivirus behavior or performance claims have been validated. Upstream licenses must be reviewed before redistributing code or binaries.
