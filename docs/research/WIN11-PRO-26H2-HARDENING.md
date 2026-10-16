# Windows 11 Pro 26H2 privacy and desktop hardening plan

**Status: research/design only; no system changes in this PR.** Target: clean Windows 11 Pro x64 26H2 build 26300.9711 running inside the isolated `uindos-test` VirtualBox VM. This plan reflects user priorities as of 2026-10-16. For each implementation, verify functionality on that build; setting a value is not proof that it took effect.

## Confirmed VM progress and baseline prerequisites

- PR #7 fixed the provisioned-AppX probe: 48 provisioned packages enumerated and 13/13 inventory probes succeeded.
- PR #8 was applied on the VM: current-user removal returned `completed`, 19 removed, none remaining (journal `35696322-d7de-4062-8476-bc5f1ec5f6b3`); new-user deprovisioning returned `completed`, 19 removed, none remaining (journal `36e1e4d6-c0cf-421d-8b8b-e3e65ec87d88`). Independent post-deprovision enumeration, post-reboot health, and fresh inventory are **still pending**.
- PR #9, now merged, added exact AppX names for Quick Assist / Get Help / Get Started and a separate reversible taskbar-visibility command. It has not been confirmed applied in the VM. Keep `Microsoft.StartExperiencesApp` out of AppX removal; it is not proven to be `Microsoft.Getstarted`.
- Before additional mutation: independently verify the provisioned list, run `uindos-baseline.ps1` after a reboot, export via VM shared folder and take a new *post-PR8* VM snapshot only once health checks pass. Preserve Snapshot 03 as original test baseline.

## Privacy surfaces and implementation classification

| Feature / requested outcome | Target mechanism | Edition and confidence | Guardrails / acceptance |
| --- | --- | --- | --- |
| Suppress post-update Welcome Experience, 'finish setting up device', tips, feature suggestions | Inspect Settings > System > Notifications > Additional settings; read current `ContentDeliveryManager` HKCU values and Windows Spotlight controls, implement only observed and version-tested user preferences | UI controls exist on Windows 11; some Experience CSP machine/user policies for Spotlight/consumer features explicitly **do not apply to Pro**. Do not mistake policy writes for effectiveness | Reversible captured state; test settings UI and first sign-in after an update / after feature update; never inhibit genuine initial account/device setup |
| Suppress Start suggested apps, recommendations, web/cloud content and account prompts | Test Start Personalization preferences and the relevant supported Search and Cloud Content policies, including Start/search separate surfaces | Pro policy support varies; `AllowWindowsConsumerFeatures` **not supported on Pro** | No `DisableSearch=1` (would remove local Search UI); test local apps/files and keyboard search after disabling web suggestions |
| Disable Widgets taskbar/board | Existing PR #9 taskbar `TaskbarDa=0` preference; optionally machine policy `HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests=0` | `AllowNewsAndInterests` is **documented for Pro**; a stronger policy than merely hiding the icon | Reversible HKLM action with admin-only apply; verify taskbar, Win+W and Widgets behavior; do not delete shell package by default |
| Remove lock-screen weather/widgets, Spotlight tips and ads | Lock screen Settings Widgets Off (or status None where UI shows legacy mode); choose Picture/Solid-background option rather than Windows Spotlight | Microsoft documents current UI and recent variants; `DisableWidgetsOnLockScreen` CSP currently preview-gated: **do not ship it as a Pro default** | Validate actual lockscreen after sign-out/reboot; preserve Windows Hello/sign-in |
| Reduce diagnostics, advertising, activity history and app recommendations | Comprehensive *read-only* audit of per-user preferences, Windows Update-adjacent policies, permissions (location, camera, microphone), feedback frequency, personalized experiences; then exact curated changes | Pro required diagnostics cannot be honestly represented as zero; do not set unsupported enterprise-only 'diagnostic off' policies | Audit `desired`, `configured`, `effective-observed`, `unsupported`, `pending`; respect original user choice to keep Location enabled unless deliberately changed |
| Block telemetry / ad domains | **Research and measure first**: official endpoint catalog for **non-Enterprise** editions + local egress capture; optional, explicit, reversible allowlist-based HOSTS/DNS module as later phase | HOSTS mappings are exact names, cannot wildcard; Microsoft infrastructure overlaps servicing, identity, updates, Defender and Store. TLS pinning and encrypted DNS can complicate measurement | No default HOSTS or firewall blocklists; no blocking Defender, Windows Update, WebView2, SmartScreen, certificate, authentication, Store, license or gaming endpoints. Require pre/post captured network evidence, regression and rollback. No 'zero telemetry' claims |

## Consumer apps, services and shell

| Item | Plan | Risk / requirements |
| --- | --- | --- |
| Quick Assist (`MicrosoftCorporationII.QuickAssist`) / Get Help (`Microsoft.GetHelp`) | Already in PR #9 curated AppX list; re-run current-user and deprovision **preview** and then explicitly apply to any recognized remaining packages | Package publisher/version validation; no broad wildcard |
| Get Started | Look for exact `Microsoft.Getstarted` AppX package; if absent, inspect Windows 26H2 installed-app entry and Start Experience associations before any alternate removal | Never equate `Microsoft.StartExperiencesApp` with a disposable Get Started app without VM proof |
| Microsoft Bing | Identify exact installed-app product/ package: VM baseline showed `Microsoft.BingSearch`, distinct from BingNews/BingWeather. Scope a separate AppX proposal gated by Start/Search health checks | Cannot disable Windows Search, indexing, or Start accidentally |
| WhatsApp/LinkedIn Start tiles | They may be recommendations/promotion placeholders or installed packaged/PWA apps. Enumerate exact AppX/AUMIDs, Win32 entries, shortcuts and registered pins first; remove placeholders from pinned layout, not from OS by name pattern | Don't automatically uninstall a user-installed app just because a tile exists |
| OneDrive (`Microsoft OneDrive` Win32) | Separate user-consented `winget`/registered official uninstall procedure after preflight: sync/account state, Desktop/Documents/Pictures folder backup and Files On-Demand placeholders, then unlink/quit safely, official uninstall, verify app gone, leave synced files and folders alone | Never `Remove-Item` OneDrive folders, never delete cloud data, avoid preventing file recovery; OS upgrades may reinstall |
| Edge Browser / Edge Update | Independently inventory Edge browser, Edge Update, WebView2 runtime and dependent app packages; research US non-EEA supported uninstall options; remove browser only if secure, reversible, and verified | **No default forced uninstall** or shared updater deletion; official Edge uninstall policy restricted to eligible EEA machines; keep WebView2 security servicing and SmartScreen |
| Widgets packages (`MicrosoftWindows.Client.WebExperience`, `Microsoft.WidgetsPlatformRuntime`) | Default **disable**, not delete. Evaluate AppX removal/deprovision only in later high-risk VM experiment if disabling is insufficient | Can affect Search, other UI integration and component registration; preserve OS update servicing |

## Minimal desktop & Explorer

| Request | Proposed action | Evidence / limits |
| --- | --- | --- |
| Dark mode | Current user `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`: set `AppsUseLightTheme=0`, `SystemUsesLightTheme=0` through the guarded transaction adapter | Documented Windows theme preferences; backup/undo and verify Explorer, Settings and Start separately |
| Solid-black wallpaper | Prefer Windows built-in **Personalization > Background > Solid color > Black**. For automation, capture wallpaper, background mode and color before applying through appropriate supported per-user APIs | Do not create/download image assets or delete original wallpaper files; app may still use cached/theme-specific wallpaper |
| Explorer clean view | Research `LaunchTo` (This PC vs Home), recent/frequent items, cloud recommendations and Gallery; favor existing UI and supported FileExplorer policy `DisableGraphRecentItems` (Pro) when appropriate | Avoid disabling Quick Access or file opening; do not remove Explorer/Start shell |
| Start and taskbar pins | Keep separate from Widgets/visibility. Investigate `ConfigureStartPins` empty `pinnedList: []` with **applyOnce** on supported 24H2+/26H2 builds; for taskbar, Microsoft XML pinned-item policy may **not** replace user-created pins | Backup/restore, no deleting Start cache databases, Taskband binaries or user shortcuts; validate pins don't reappear after sign-out/new user |
| Windows 10-style right-click | Treat CLSID registry trick / third-party Explorer patches as **unsupported, build-sensitive experiments**; no default registry injection unless it works reliably on 26H2 and undo is verified. `Show more options` is stable fallback | Explorer updates can break hack; do not inject unsigned shell extensions or replace Explorer |
| File indexing | Preserve classic indexing for now. If stock Search remains primary, test **Enhanced** mode from Settings > Privacy & security > Search > Find my files; if a proven local Spotlight-style launcher is selected, benchmark that first | Enhanced scans most of PC, may increase CPU/battery and index contents of private files locally; don't promise it improves privacy. Keep indexing service enabled until alternative works |
| Remove Windows wallpaper assets, Bing / Spotlight wallpaper features | Disable Spotlight and ad surfacing rather than deleting `%WINDIR%` wallpaper assets; revisit storage cleanup only using supported component/servicing interfaces, after size and persistence measurements | Never delete protected system wallpaper resources by default or rely on hypothetical performance benefit |

## PR execution sequence (each separately reviewable)

1. **PR #11 — Notification / post-update OOBE & privacy audit.** Add read-only detector and reversible per-user preference adapter for verified notification suggestions, Welcome Experience, recommendation toggles; explicitly label controls which Windows Pro doesn't support. VM proves on/off after sign-out and updates. Preserve allowed location access.
2. **PR #12 — OneDrive and residual app cleanup.** Build exact Win32 OneDrive detection/unlink-and-uninstall plan with explicit consent, separate from AppX; validate PR #9 new app targets; BingSearch/WhatsApp/LinkedIn detection only until package identity and Search risks are resolved.
3. **PR #13 — Widgets and lock screen.** Documented Pro device policy + per-user lock-screen UI/settings behavior, no package deletion by default; test after login, lock and reboot.
4. **PR #14 — Visual desktop and Explorer.** Reversible dark mode, solid-black wallpaper, Explorer Home/recent/cloud-content choices, taskbar/start pins policy validation; test rollback & user customization survival.
5. **PR #15 — Search/indexer and context menus.** Web suggestions suppression with verified local search, measured Enhanced indexing or future replacement launcher, experimental Win10 context-menu behavior only if supported and stable.
6. **PR #16 — Network privacy measurement.** Categorize observed Microsoft endpoints and measured egress; no default HOSTS deployment until narrowly scoped test proves updates/security/gaming unaffected.
7. **Separate Edge research/VM gate:** browser-only removal, preserve WebView2/Edge updater security, unsupported-region boundaries, recoverability.

## Safety and test gate

- Read-only inspection must be possible before writing any registry value, HOSTS line, package manifest, Start layout or installer state.
- Record exact old values, apply and verify, make undo available where feasible; explicit consent/snapshot for irreversible operations.
- Reboot, logoff and Windows Update regression gate: Defender antivirus/tamper, Firewall, UAC, Windows Update, Store/WinGet, WebView2, local Start Search, Windows Hello, Quick Assist replacement and Xbox/gaming launch where available.
- Distinguish installed package, provisioned package, pinned link, promotional shortcut, Win32 install, optional Windows feature, policy and taskbar/lockscreen widget.
- Compare baseline JSON before and after; never infer no telemetry from registry value alone. Capture no credentials, account files, traffic payloads, or identifying endpoints in public test logs.

## Source links (reviewed 2026-10-16)

- Experience CSP (edition matrix, consumer features, Windows tips, Welcome Experience, tailored experiences): https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience
- NewsAndInterests CSP (Widgets policy for Pro, preview-only lock-screen policy): https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests
- Search CSP (SearchHighlights versus entirely disabling Search): https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search
- OneDrive supported uninstall: https://support.microsoft.com/en-us/onedrive/turn-off-disable-or-uninstall-onedrive
- Microsoft Edge Update uninstall policy EEA restriction: https://learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies
- Windows 11 non-Enterprise network endpoints: https://learn.microsoft.com/en-us/windows/privacy/windows-11-endpoints-non-enterprise-editions
- Windows 11 diagnostics by edition: https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization
- File Explorer cloud recent item policy: https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-fileexplorer
- Windows 11 personalization DWORDs: https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-common
- Lock screen user controls: https://support.microsoft.com/en-us/windows/experience/personalization/customize-the-lock-screen-in-windows
- Search indexing Classic versus Enhanced: https://support.microsoft.com/en-us/windows/experience/performance-optimization/search-indexing-in-windows
- Windows 11 Start pinned-layout policy and applyOnce: https://learn.microsoft.com/en-us/windows/configuration/customize-start-menu-layout-windows-11
- Windows 11 taskbar pin limitations: https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps
