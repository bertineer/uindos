# Curated consumer and media AppX removal — Windows 11 Pro

**PR #8 (VM testing pending).** An opinionated list of **21 exact AppX package names**, not a general debloat catalog.

## Curated list

| Category | Exact package names |
| --- | --- |
| Original consumer targets | Microsoft.Copilot, Microsoft.BingNews, Microsoft.BingWeather, Microsoft.WindowsFeedbackHub, Microsoft.MicrosoftSolitaireCollection |
| Media applications | Clipchamp.Clipchamp, Microsoft.ZuneMusic (Media Player / Groove), Microsoft.ZuneVideo (Movies & TV), Microsoft.WindowsSoundRecorder, Microsoft.WindowsCamera, Microsoft.Windows.Photos, Microsoft.Paint |
| Other consumer/cloud apps | Microsoft.MicrosoftOfficeHub, Microsoft.OutlookForWindows, MSTeams, Microsoft.MicrosoftStickyNotes, Microsoft.Todos, Microsoft.PowerAutomateDesktop, Microsoft.Windows.DevHome, Microsoft.YourPhone, Microsoft.WindowsAlarms |

The 2026-10-16 Windows 11 Pro 26H2 build 26300.9711 test baseline contains **19 of these 21** in provisioning; Copilot and ZuneVideo are absent. Clipchamp has publisher identity `yxz26nhyzhsrt`; all other listed packages use publisher `8wekyb3d8bbwe`. Identity/version/publisher drift blocks removal. Absence is a normal, reported state.

**Never removed by these commands:** Microsoft Store, WinGet/App Installer, Windows Security, Windows Update, Edge/WebView2, gaming/Xbox, Calculator, Notepad, Snipping Tool, app runtimes/frameworks, AV1/HEVC/VP9/HEIF/WebP codecs or system media APIs. The legacy Windows Media Player optional feature is not an AppX target and is **not** modified in this PR. We are removing the media apps, not trying to strip Windows Pro into a potentially broken Pro N installation.

**Important:** Photos/Paint/Camera/Media Player are deliberately removed without installing replacements. Choose and install suitable image/media tools separately. App removal may delete user data.

## Two separate scopes

Windows separates packages installed for **existing user accounts** from packages **provisioned for future user accounts**. Microsoft's provisioning cmdlet does not remove existing users' apps. These are two different commands with two distinct explicit confirmations.

### Existing/current user (PowerShell 7, normal user)

Run under the user whose apps should be uninstalled. Default is preview; no writes:

~~~powershell
pwsh -NoProfile -File ./bin/uindos-debloat.ps1
~~~

After reviewing the plan and accepting possible data loss:

~~~powershell
pwsh -NoProfile -File ./bin/uindos-debloat.ps1 -Apply -AcceptAppDataLoss
~~~

Uses exact current-user Get-AppxPackage / Remove-AppxPackage calls. No other users are affected. The journal lives under %LOCALAPPDATA%\uindos\transactions\app-removal-v1.

### New users only (PowerShell 7 **as Administrator**)

Read-only preview:

~~~powershell
pwsh -NoProfile -File ./bin/uindos-deprovision.ps1
~~~

Explicit deprovisioning:

~~~powershell
pwsh -NoProfile -File ./bin/uindos-deprovision.ps1 -Apply -AcceptDeprovisioning
~~~

The implementation deliberately uses an inbox Windows PowerShell **5.1** child process for provisioned servicing: PowerShell 7.6.7 fails the DISM cmdlet with COM 0x80040154 on our clean Windows 11 Pro 26H2 VM, whereas 5.1 and DISM.exe work. The child receives a constant encoded local script, returns schema-checked JSON, and performs *only exact package-name* Get-AppxProvisionedPackage and Remove-AppxProvisionedPackage -Online operations. **No -AllUsers argument** is used.

Deprovisioning affects new accounts created later, **not existing profiles**. Future Windows updates or explicit Store installations can reinstall an app; this does not promise permanent anti-reinstallation.

Both operations use an exclusive journal lock, read-before-write checks, exact publisher/version validation, per-item journal phases, post-removal verification and idempotent reruns. Deprovision journals are under %LOCALAPPDATA%\uindos\transactions\app-deprovision-v1. A blocked item prevents the batch starting; errors midway return needs-review (CLI exit code 2). Raw exception paths are not written to journals.

**Neither AppX removal nor deprovisioning can be automatically undone.** A journal is not a restoration mechanism. Application data can be lost. Use the disposable VM snapshot for recovery; do not test apply on a primary Windows machine until the VM gate below passes.

## Verification gate

1. Restore the disposable Windows 11 Pro snapshot **03 - uindos Testing Environment**.
2. Capture a read-only pre-change baseline and inspect both 21-item preview plans; expect approximately 19 provisioned entries on build 26300.9711.
3. Compare provisioned package full identities against Windows PowerShell 5.1 Get-AppxProvisionedPackage -Online before any apply.
4. Run current-user apply; preview again; inspect its journal.
5. Run elevated deprovision apply; preview again; inspect its journal and independently enumerate provisioned packages.
6. Reboot and test Windows Update, Defender, Store, WinGet, WebView2, Windows Search, audio/camera APIs, and gaming components. For provisioning, optionally create a test user to check that the removed provisioned apps do not appear.
7. Restore snapshot. Compare post-operation AppX counts, disk usage and startup overhead only with measured evidence.

The CI tests include mock-only current-user and provisioning tests on Windows and Linux, plus hosted Windows **read-only** current-user package detection. CI never removes a package.

## Official guidance

- [Microsoft: installed vs provisioned packages](https://learn.microsoft.com/en-us/windows/application-management/provisioned-apps-windows-client-os)
- [Microsoft: Remove-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage)
- [Microsoft: Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage)
- [Microsoft: deprovisioning and upgrades](https://learn.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update)
- [Research sources](research/SOURCES.md)
