# Appearance defaults

The curated current-user appearance is dark Windows/app color modes and a
solid-black desktop. This module does not install a theme package or generate
wallpaper images. Preview is read-only:

```powershell
pwsh -NoProfile -File ./bin/uindos-appearance.ps1
```

Apply from the same **non-elevated** user/session as Explorer:

```powershell
pwsh -NoProfile -File ./bin/uindos-appearance.ps1 -Apply
```

It sets the two documented per-user color-mode DWORDs to dark and uses the
Windows desktop API to show black instead of a wallpaper image. An existing
solid-color desktop keeps its background enable state; only its color needs
changing. Wallpaper files and the saved image/slideshow source are preserved.

The module checks Windows 11 Pro/Pro N x64/ARM64, checks native API HRESULTs,
journals exact prior managed state, verifies readback, and refuses undo when
managed state has drifted. Repeated Apply to the desired state creates no new
transaction. Theme refresh is a bounded best-effort notification; inspect the
actual desktop, Explorer and Settings separately. Some apps need reopening.

## Recovery

Keep the returned transaction ID and its **private** journal. Default location:
`%LOCALAPPDATA%\uindos\transactions\appearance-v1`. A private durable directory
may be provided with `-JournalDirectory`, including on Apply and Undo:

```powershell
pwsh -NoProfile -File ./bin/uindos-appearance.ps1 -Undo <transaction-guid>
```

Undo restores the original two theme values (including absence), exact
background color, and image visibility when this module disabled a visible
image. It does not directly write wallpaper paths or recreate missing original
files. Windows may change its own registry reference to a transcoded cache path
while restoring the same visible wallpaper; those internal paths are not part
of the exact managed-state rollback contract.
Windows retains recent-image history, and a slideshow's previous position/time
is not restored. Native/API or journal failures can require review rather than
claiming complete rollback. Do not automatically undo against a reverted VM.

## Scope and limits

These are user appearance preferences, not a forced organizational policy or
new-user provisioning. An app can ignore dark mode or use its own theme.
High-contrast/accessibility themes, remote-session background suppression and
changing monitor configurations need independent validation. The desktop API
does not promise to disable Spotlight acquisition or change the Settings
Background selection; a later wallpaper/slideshow change may enable imagery
again. Verify current-session appearance and reboot persistence separately.
Lock-screen preferences are a separate surface.

The command does not change security, updates, app installation, local Search,
desktop data or the Explorer fallback. No process is restarted or kept running.
See [sources and applicability](research/APPEARANCE-DEFAULTS.md).

## Validation

Portable tests:

```powershell
pwsh -NoProfile -File ./tests/theme-mock.ps1
pwsh -NoProfile -File ./tests/desktop-background-mock.ps1
pwsh -NoProfile -File ./tests/appearance-mock.ps1
```

VM acceptance: save preview, Apply, verify actual black desktop and dark UI,
repeat Apply, Undo and compare exact managed prior state, then intentionally
reapply only after rollback succeeds. Use a private durable journal directory.
Collect Windows/security/dependency checks as appropriate; coordinate any
reboot/sign-out. Mocks are not evidence of on-device shell behavior.

On the Windows 11 Pro build 26300.9711 VM, non-elevated preview showed three
pending changes (background color was already black). Apply, repeat Apply
unchanged, Undo with zero conflicts, and final intentional reapply passed.
All four managed states restored exactly during Undo and the original beach
wallpaper visibly returned; Windows changed its internal image reference to
`TranscodedWallpaper`. Private evidence records this distinction rather than
claiming byte-for-byte restoration of Windows' cached personalization state.

The final desktop was black, Explorer and Settings rendered dark, and Colors
reported Dark. The taskbar remained visually light in that session even with
SystemUsesLightTheme=0. Its refresh and reboot persistence remain pending a
coordinated session restart. No restart, sign-out or process termination ran.
