# AppX and Copilot removal research — PR #6

**Audit date:** 2026-10-16. The cited Microsoft documentation is authoritative for command semantics; source code and packaging vary by build and install origin. GitHub-hosted read-only CI is not proof of complete compatibility.

## Microsoft source interpretation

1. [Copilot management](https://learn.microsoft.com/en-us/windows/client-management/manage-windows-copilot) explicitly documents finding `Microsoft.Copilot` with `Get-AppxPackage -Name` and removing the found full package name using `Remove-AppxPackage`. The legacy `TurnOffWindowsCopilot` policy does not comprehensively control the new Copilot application.
2. [Remove-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage): without `-AllUsers` or `-User`, removes the specified AppX package from the **current account**. It is not Windows component servicing and is not a data-preserving rollback.
3. [Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage): removes a provisioned package so newly created accounts do not receive it; existing accounts are unaffected. This requires a separate administrative phase and is *not included*.
4. [Keep provisioned apps removed across feature updates](https://learn.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update): Windows feature updates and package deprovisioning have separate state/behavior. Do not claim that simply uninstalling an app for one user is update-proof.
5. [Policy-based removal of preinstalled Microsoft Store apps](https://support.microsoft.com/en-us/servicing/os/windows/docs/2025/08/policy-based-removal-of-pre-installed-microsoft-store-apps): newer managed-device options exist, but availability differs by Windows edition and management setup; not assumed available for ordinary Windows 11 Pro personal use.

## Scope decision

Initial curated user apps: `Microsoft.Copilot`, `Microsoft.BingNews`, `Microsoft.BingWeather`, `Microsoft.WindowsFeedbackHub`, `Microsoft.MicrosoftSolitaireCollection`.

Names and publisher ID are checked on the machine, not assumed present. Exclude Store, App Installer, Windows Security, framework/resource packages, WebView2, system components, Photos, Xbox and Gaming Services. The presence of a package does **not** prove it was unwanted by a prior user: uninstall can remove user data. Require explicit acceptance.

## Limitations to close in later PRs

- Test package identities and availability on Windows 11 Pro 24H2/25H2/26H2 (supported builds as available), local and Microsoft accounts.
- Determine whether each AppX identity is provisioned for new accounts, and whether it reappears after feature/cumulative updates. Consider Windows-supported administrative removal with a separate verified rollback strategy.
- Assess Copilot as an AppX app vs browser webapp/standalone Win32 installer and Start/menu integration; do not wildcard delete any path called 'Copilot'.
- UI accessibility after removal, Microsoft Store reinstall pathways and possible local app-data effects.
- Measure idle RAM/CPU/disk only after verifying causal effects, not assuming that an uninstall saves runtime resources.
- Windows 11 Pro/Pro N x64 and ARM64 are implementation gates; Home and Enterprise require explicit testing.
- Future script must handle newly discovered package identities through review, not silent wildcard expansion.

## Hard prohibitions

No blanket `Get-AppxPackage -AllUsers | Remove-AppxPackage`, no framework or runtime package removals, no generic user-supplied package removal arguments, no direct deleting `WindowsApps` files, no Defender/SmartScreen weakening, no Windows Update or repair-health service blocking, and no user-profile deletion.

A package-removal journal is evidence of what was attempted and checked. It is **not** a means to reconstruct uninstalled code or user data.
