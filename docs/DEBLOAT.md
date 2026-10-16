# Curated consumer app removal — initial phase

**Status:** PR #6; applies to **Windows 11 Pro/Pro N x64 and ARM64, current user only**. It is a small part of uindos's opinionated foundation, not a general AppX/package manager.

## The curated list

| AppX name | Purpose | Default disposition |
| --- | --- | --- |
| Microsoft.Copilot | Microsoft consumer Copilot app | Remove if safely identified |
| Microsoft.BingNews | News | Remove if safely identified |
| Microsoft.BingWeather | Weather | Remove if safely identified |
| Microsoft.WindowsFeedbackHub | Feedback Hub | Remove if safely identified |
| Microsoft.MicrosoftSolitaireCollection | Solitaire Collection | Remove if safely identified |

A currently missing app is reported as **absent**, not a failed removal. If a package's identity, publisher ID or type is unexpected, it is **blocked** and no removal begins. This is deliberately a fixed, small list—not a manifest where callers supply arbitrary package names.

**Explicitly preserved:** Microsoft Store, Microsoft Desktop App Installer/WinGet, AppX/MSIX frameworks, WebView2, Edge (pending separate review), Photos, Gaming Services, Xbox apps/overlays, Game Bar, Windows Security, and all user-installed Win32 software.

Note that a curated package may have been deliberately installed or actively used. **Uninstall may remove its local app data.** Review the list before applying.

## Usage

From a standard, non-elevated PowerShell 7 terminal running under the Windows account being configured:

~~~powershell
# Inspection only: writes nothing, prints a JSON plan.
pwsh -NoProfile -File ./bin/uindos-debloat.ps1

# Only after reviewing the plan: remove eligible packages from current user.
pwsh -NoProfile -File ./bin/uindos-debloat.ps1 -Apply -AcceptAppDataLoss
~~~

**No automatic undo command is offered.** Removing an AppX package may remove app-specific data, and the package may not be locally reinstallable. Some apps can be reinstalled from an official Microsoft Store source later, but that does not reconstruct lost app data. Do not test removal on a primary Windows installation before Windows VM verification.

## Execution contract

- Uses only Windows' built-in `Get-AppxPackage -Name` and `Remove-AppxPackage -Package` for **the current account**.
- Requires Windows 11 Pro/Pro N version/build validation and both explicit apply/accept-data-loss switches.
- Enumerates the five fixed package names, checks exact names and full package identities, Microsoft's packaged publisher ID `8wekyb3d8bbwe`, and refuses framework, resource or non-removable packages.
- Writes a timestamped JSON journal under `%LOCALAPPDATA%\uindos\transactions\app-removal-v1` **before** the first package removal, marks each operation individually, and verifies absence after removal.
- Stops on a mismatch or removal error, returns `needs-review` and a non-zero CLI exit code (2), and never claims previous packages have been restored.
- If none of these apps is installed for the current account, returns `unchanged` without writing a journal.
- Repeated runs only propose what is still installed for the current account.

**Important:** this is *not* an ACID transaction or recoverable Windows package snapshot. If the process is forcibly terminated during removal, the journal may have a `removing` step and will require manual assessment. Do not upload journals without inspecting them; installed application names and versions are included.

## What this phase cannot achieve

Windows has distinct notions of **installed AppX for the current user**, **installed for other users**, and **provisioned packages for accounts created later**. Microsoft's [Remove-AppxPackage documentation](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage) and [Remove-AppxProvisionedPackage documentation](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage) describe these separate operations.

This stage **does not**:
- Remove provisioned packages from the Windows image or affect any other user's applications.
- Prevent Windows upgrades, Store, Microsoft-account experiences or provisioning from reinstalling an app.
- Block every form of Copilot (browser, Office, other integration or shortcuts).
- Disable services, scheduled tasks, Windows Update, Defender, SmartScreen, BitLocker or Windows Components.
- Uninstall Microsoft Edge or WebView2.
- Erase Windows diagnostics or guarantee measured performance improvement.

Future PRs can examine provisioning, reinstallation after updates, Copilot experience variants and Edge removal separately, with their own privileged execution boundaries and recovery plans.

## Validation status

Automated tests use mock AppX providers on Windows and Ubuntu, including identity rejection, consent gating, read-only planning, no-op runs, partial failures and journaling. Windows-hosted CI also enumerates real AppX **read-only** and does **not** uninstall anything.

**Real removal has not been tested on a disposable Windows 11 Pro VM yet.** Before designating this stage production-ready, perform apply/partial-failure/reboot/update/restore-path testing in an isolated Windows 11 Pro VM. Record the exact build, packages and results; ensure Microsoft Store, WinGet, WebView2, Windows Update, Defender and gaming components remain functional.

## References

- [Microsoft: remove or prevent installation of the Microsoft Copilot app](https://learn.microsoft.com/en-us/windows/client-management/manage-windows-copilot)
- [Microsoft: Remove-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage)
- [Microsoft: Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage)
- [Microsoft: Keeping removed provisioned apps from returning during an update](https://learn.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update)
- [Microsoft: Policy-based removal of preinstalled Microsoft Store apps](https://support.microsoft.com/en-us/servicing/os/windows/docs/2025/08/policy-based-removal-of-pre-installed-microsoft-store-apps)

See [research/APPX-REMOVAL.md](research/APPX-REMOVAL.md) for known ambiguities and future scope.
