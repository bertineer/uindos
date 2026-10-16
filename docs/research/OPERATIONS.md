# Candidate Windows operations and uindos disposition

This is a **triage matrix, not executable instructions**. References are pinned in [SOURCES.md](SOURCES.md). Decisions apply to *uindos defaults*, not to other tools' intent or quality.

## Privacy / AI / advertising

| Candidate operation | Source evidence | Disposition | Reason and acceptance requirement |
| --- | --- | --- | --- |
| Advertising ID, tailored experiences, inking/typing personalization and activity publishing | [Win11Debloat telemetry .reg](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Regfiles/Disable_Telemetry.reg) | ADOPT | Respect consent settings; verify per-user values, avoid claiming complete telemetry disablement. |
| `AllowTelemetry=0` universally means diagnostics disabled | [Win11Debloat .reg](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Regfiles/Disable_Telemetry.reg); [Microsoft policy](https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization) | REJECT | Not an effective diagnostic-data-off setting on standard Windows Pro. Detect OS edition; report minimum effective level. |
| Disable consumer promotions and suggested third-party apps | [WinUtil ConsumerFeatures](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/config/tweaks.json); [Microsoft policy](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience) | ADAPT | CSP/Group Policy not applicable to Pro; use tested Pro-relevant user settings, app provisioning and drift detection. |
| Remove installed Microsoft Copilot app and provisioned copies | [Win11Debloat app list](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/Apps.json); [WinUtil appx](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/config/appx.json) | ADOPT | Enumerate actual installed/provisioned/WinGet identifiers on each build; verify across sign-in and upgrade. |
| Disable Recall, Click to Do, app AI integrations | [Win11Debloat features](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/Features.json); [Microsoft WindowsAI CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai) | ADAPT | Edition/build-gate; independently disable/remove feature entry points and components as supported. |
| Use old `TurnOffWindowsCopilot` as full Copilot protection | [Win11Debloat Copilot .reg](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Regfiles/Disable_Copilot.reg); [Microsoft WindowsAI CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai) | REJECT | Deprecated policy doesn't control every new Copilot app experience. |
| Remove selected diagnostic/CEIP scheduled tasks | [Win11Debloat list](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Scripts/Features/Telemetry-ScheduledTasks.ps1) | RESEARCH | Inventory exact task purpose on target build; disable only if serving no update, compatibility or repair function. |
| Blanket blocking Microsoft domains and claiming zero telemetry | [Microsoft connected service guidance](https://learn.microsoft.com/en-us/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services) | REJECT | High risk to Windows Update, signing, licensing and security. Use measured classification and narrow validated policies. |

## App removal and footprint

| Candidate operation | Source evidence | Disposition | Reason and acceptance requirement |
| --- | --- | --- | --- |
| Remove only curated nonessential AppX packages | [Win11Debloat app catalog](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/Apps.json) | ADOPT | Maintain short opinionated list and dependency/safety notes. |
| Deprovision packages for new accounts as well as removing for current users | [Win11Debloat removal](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Scripts/AppRemoval/Remove-SelectedApps.ps1#L252-L300); [WinUtil helper](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/functions/private/Remove-WinUtilProvisionedAPPX.ps1) | ADAPT | Distinguish installed user, all users and provisioning; preserve Store/Framework dependencies. |
| Force remove the Edge **browser** | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1#L41-L126) | RESEARCH | Explicit project requirement; evaluate supported availability, unsupported techniques, upgrade regression and rollback. |
| Remove EdgeWebView2 and Edge Update indiscriminately | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1#L45-L112); [Microsoft WebView2](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/evergreen-vs-fixed-version) | REJECT | WebView2 and its security updates serve independent apps; don't delete all of `Program Files (x86)\Microsoft`. |
| Remove optional capabilities via DISM/Windows servicing | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1#L160-L215) | ADAPT | Use a reviewed allowlist with feature dependencies, repair/install regressions and measured savings. |
| Force-remove every legacy feature / UWP application | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1#L128-L215) | REJECT | Removes capabilities relied upon by installers, optional features, security and applications. |
| Remove OneDrive | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1#L235-L248) | ADAPT | Check file sync/known-folder redirection/data migration before uninstall. |
| Uninstall drivers with DDU automatically in Safe Mode | [WinSux bootstrap](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/winsux.ps1#L80-L135); [step one](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/stepone.ps1#L150-L153) | OUT OF SCOPE | Not part of a reproducible privacy or desktop setup; risks GPU/audio availability. |

## Security / Windows servicing

| Candidate operation | Source evidence | Disposition | Reason and acceptance requirement |
| --- | --- | --- | --- |
| Run installers elevated only for specific supported changes | [WinSux bootstrap](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/winsux.ps1#L1-L25) | ADAPT | Scope privilege; never run downloaded mutable code as administrator. |
| Switch into Safe Mode, modify TrustedInstaller binary path, execute there | [WinSux step one](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/stepone.ps1#L1-L38) | REJECT | Changes protected service execution identity and complex boot state; unnecessary for intended changes. |
| Keep Defender realtime but turn off cloud, tamper and other protection | [WinSux step one](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/stepone.ps1#L38-L118) | REJECT | Material security regression; security telemetry tradeoffs should not be hidden. |
| Turn off all SmartScreen components because Edge is removed | [WinSux step one](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/stepone.ps1#L89-L112) | REJECT | Windows application/download reputation checks are independent from browser-only SmartScreen. |
| Decrypt BitLocker-encrypted drives | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1#L435-L444) | REJECT | Removing at-rest protection is unrelated to reducing vendor telemetry. |
| Disable Windows Update services, schedule, WSUS endpoint | [WinUtil MicroWin](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/functions/private/Invoke-WinUtilISOScript.ps1#L585-L643) | REJECT | Explicitly disables BITS, wuauserv, UsoSvc, WaaSMedicSvc and points to localhost:8080. |
| Delete global RunOnce keys, third-party tasks/startups | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1#L320-L352) | REJECT | May erase application install completion, vendor services and user configuration. |
| Deep Windows Update repair by deleting whole policy trees | [WinUtil update repair](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/functions/public/Invoke-WPFFixesUpdate.ps1#L123-L155) | REJECT | Destroys unrelated configuration; beyond scope of safe privacy optimization. |
| Take restore point and snapshot exact changed registry settings | [Win11Debloat change orchestrator](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Scripts/Features/Invoke-Changes.ps1#L330-L453) | ADAPT | Snapshot-before-action and verify restore. System Restore is supplementary, not full transactional undo. |

## Performance

| Candidate operation | Source evidence | Disposition | Reason and acceptance requirement |
| --- | --- | --- | --- |
| Reduce unused startup/background apps and promotional widgets | [Win11Debloat features](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/Features.json) | ADOPT | Quantify idle CPU, memory, boot time, network overhead and app functionality. |
| Force 'ultimate performance' power plan for every device | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1) | ADAPT | Consider desktop-only measured benefit; avoid reducing laptop battery life. |
| Permanent custom timer resolution service | [WinSux timer source](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/settimerresolutionservice.cs) | RESEARCH | Benchmark latency, battery/idle power and game frametimes; reject by default without benefit. |
| Disable memory compression universally | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1#L432-L434) | REJECT | Can increase paging and memory pressure; requires repeatable benchmark to justify exception. |
| Disable or bypass VBS/security features for FPS | [WinSux step one](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/stepone.ps1#L120-L148) | REJECT | Security cost too high for an unquantified default performance claim. |
| Aggressively remove system caches and component store by filesystem deletion | [WinSux steptwo](https://github.com/bertineer/winzep/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1) | REJECT | Use documented servicing and cleanup APIs, not raw deletion of Windows internals. |

## Engineering patterns worth reusing conceptually

- **Source-linked manifests and version-gated feature descriptions:** [Win11Debloat Features.json](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/Features.json).
- **App risk classification and user/provisioned separation:** [Win11Debloat Apps.json](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Config/Apps.json).
- **Exact-registry-state capture, undo, and dry-run:** [Win11Debloat backup and change flow](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Scripts/Features/Backup-RegistrySnapshotCapture.ps1).
- **Installation-media customization as a possible future stage:** [MicroWin source](https://github.com/ChrisTitusTech/winutil/blob/07ccd8e2e755a706f31569808b31f5b77acad6a9/functions/private/Invoke-WinUtilISOScript.ps1) — **not its update-disabling implementation**.

**Next:** translate a small ADOPT/ADAPT subset into read-only detection rules before writing removal or disabling operations.
