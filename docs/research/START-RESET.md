# Start reset policy provenance and applicability

Reviewed 2026-10-16/17 against Microsoft's current documentation and the VM's
installed Administrative Template. No upstream implementation code is copied.

[Customize the Start layout](https://learn.microsoft.com/en-us/windows/configuration/start/layout)
documents JSON export through inbox Windows PowerShell `Export-StartLayout
-Path ...json`. For Windows 11, `applyOnce: true` allows later user pin edits
to persist; support begins at 24H2 with KB5062660. The GPO surface has the same
update prerequisite. Policy layout becomes effective at sign-in. Pins referring
to uninstalled apps need not appear until those apps are installed. These facts
explain why an exported layout cannot promise exact reconstruction of the VM's
absent-package WhatsApp/LinkedIn pins.

[Start policy settings](https://learn.microsoft.com/en-us/windows/configuration/start/policy-settings#configure-start-pins)
defines Configure Start Pins as replacing the current/default list and lists
both user and computer GPO scopes. uindos uses only the user scope. An empty
`pinnedList` is the chosen configuration; its actual empty-layout outcome on the
VM is pending, separate from valid policy value readback.

The VM's `C:\Windows\PolicyDefinitions\StartMenu.admx` policy
`ConfigureStartPins`, lines 586–597, defines the Explorer policy key, enabled
DWORD 1, and text element `ConfigureStartPinsJSON` with `expandable="true"`.
SHA-256 of that inspected file:
`DD419E65E02E78E370C93B34AA63C05DD958F25B0189CBD00462107D351716C7`.
The hash is a source-evidence identifier, not a runtime download or trust pin.
The correct JSON type is therefore REG_EXPAND_SZ; see the existing
[raw-registry API research](REGISTRY-EXPAND-STRING.md), including pinned .NET
source and exact-value journal tests.

Initial implementation is deliberately gated to Pro/Pro N X64/Arm64 build
26300 UBR>=9711, excluding detected preview builds. Native preview has passed
only on Pro X64 26300.9711. A broader Microsoft-supported OS is not automatically
accepted by this experimental workflow. Policy-only Undo does not use this
build gate, to allow removal after an update.

Management detection reads local join/enrollment metadata, local Group Policy
Registry.pol presence, HKCU/HKLM Explorer layout values, and current device/user
PolicyManager Start values. It blocks unknown results and does not write MDM,
PolicyManager, local GPO files or machine policy. These are conservative local
conflict signals, not a universal management discovery API.

Layout restoration and reuse of an apply-once payload are not proven. Preserve
the backup, disclose that limit, and obtain informed layout-loss acknowledgment.
Do not remove Start caches, taskbar databases, package data or internal markers.
