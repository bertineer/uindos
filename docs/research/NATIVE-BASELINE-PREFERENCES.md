# Native preference source notes

## Scope and evidence

Target: Windows 11 Pro 26H2, build 26300.9711. Start, Taskbar, and Start folder
preferences were set through native UI. Readback, unchanged repeat, restoration
of captured choices, final application and reopened-page verification passed.
The early-update switch was already Off; no update setting changed. Explorer's
native Home-to-This-PC choice passed restoration and final reopen checks.
Gallery's separate per-user experiment and limits are recorded in
[Gallery navigation validation](GALLERY-NAVIGATION-2026-10-17.md).
No production preference command or registry adapter is added here.

## Supported UI and limits

- **Start:** Microsoft documents the 26H2 menu size and independent Pinned,
  Recent, and All section controls. Keep All apps On while hiding Pinned and
  Recent. The 24H2/25H2 KB also documents size and section settings; rollout may
  vary by device. Start folders are shortcuts shown by the power button; hiding
  a shortcut does not delete its folder.
- **Recent items:** The recently opened items preference controls what appears
  in Start, File Explorer, and Jump Lists. Treat it as display/history
  suppression, not erasure. Microsoft documents separate policies for clearing
  recent-document shortcuts; those are not part of this change. Existing
  recent entries may return if display is re-enabled. Rollback is conditional
  on no later user drift and cannot reconstruct prior history.
- **Taskbar Resume:** The requested native Taskbar Resume choice is Off. Public
  support material describes Cross-device Resume under Settings > Apps >
  Resume, requiring an Android device and Link to Windows. The observed
  Taskbar badge toggle alone does not establish that every Resume or
  cross-device capability is disabled. No policy mapping is inferred.
- **Windows Update:** Set **Get the latest updates as soon as they're
  available** Off in Settings > Windows Update. Microsoft says regular
  security updates continue with the toggle On or Off; the setting controls
  priority/timing for non-security updates, features, fixes, and improvements.
  Optional updates remain separately selectable. This is not a version hold,
  does not undo installed updates, and does not disable servicing.
- **File Explorer landing:** Use **… > Options > General > Open File Explorer
  to > This PC > Apply**. This changes the opening view only.
- **Gallery:** No Microsoft-documented 26H2 Settings toggle, Gallery-specific
  Pro policy, or supported per-user registry mapping for hiding just the
  navigation item was found. Local PolicyDefinitions also had no Gallery
  policy. Microsoft documents `System.IsPinnedToNameSpaceTree` as a shell
  property describing whether a shell folder is pinned, but that does not
  document a writable Gallery mapping or support for build 26300.9711. Do not
  delete namespace registrations, Explorer, or Photos components. Gallery
  hiding therefore remains an experimental per-user change, with observed
  results restricted to this build. The linked validation records the actual
  absence/restoration cycle separately from the documented property semantics.

The VM uses a local account, so account-dependent notices and cross-device
experiences may not be observable. Private journals capture prior UI choices;
Undo must not overwrite later user changes. No RAM benefit, privacy guarantee,
or account-wide behavior is claimed. Windows security updates and servicing
remain enabled; no new software is involved.

## Microsoft sources

- [What's new in Windows 11, version 26H2](https://learn.microsoft.com/en-us/windows/whats-new/whats-new-windows-11-version-26H2) — Start size and independent section visibility.
- [August 27, 2026 update, KB5120998](https://support.microsoft.com/en-us/servicing/os/windows-11/2026/08/kb5120998-windows-11-24h2-25h2-update) — Start and Taskbar controls; gradual rollout availability.
- [Customize the Windows Start menu](https://support.microsoft.com/en-us/windows/experience/personalization/customize-the-windows-start-menu) — recommendation sections and folder shortcuts.
- [Get Windows updates as soon as they're available](https://support.microsoft.com/en-us/windows/deployment/updates-lifecycle/get-windows-updates-as-soon-as-they-re-available-for-your-device) — security-update behavior and early optional/feature update timing.
- [Windows File Explorer](https://support.microsoft.com/en-us/windows/experience/fileexplorer/file-explorer-in-windows) — This PC startup option and Gallery/Quick access context.
- [FileExplorer Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-fileexplorer) — documented Explorer policy list; no Gallery-only hide policy.
- [System.IsPinnedToNameSpaceTree](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-ispinnedtonamespacetree) — shell property semantics, not a Gallery registry procedure.
- [Cross-device Resume](https://support.microsoft.com/en-us/windows/apps/phonelink/cross-device-resume-feature) — prerequisites and documented Apps > Resume controls.
