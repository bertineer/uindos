# Dark mode and solid-black desktop — source audit

Reviewed 2026-10-16. Initial target Windows 11 Pro x64 build 26300.9711,
PowerShell 7.6.7. Version/edition gating is deliberately narrow; it is not a
claim that Microsoft restricts these desktop APIs to Pro or Windows 11.

## Theme preferences

Microsoft's [common settings registry reference](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-common)
documents `AppsUseLightTheme` and `SystemUsesLightTheme`, DWORD 0/1, at
HKCU Software\Microsoft\Windows\CurrentVersion\Themes\Personalize. Zero selects
dark app/Windows color modes. Capture existence, registry kind and exact value;
reject unsupported prior kinds. Restore JSON-deserialized DWORD numbers using
validated numeric conversion rather than requiring a boxed Int32.

[WM_SETTINGCHANGE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange)
and [SendMessageTimeout](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendmessagetimeoutw)
document bounded broadcasts after system-parameter changes. The theme-specific
`ImmersiveColorSet` section hint is treated as best-effort, build-tested refresh
behavior; the generic message documentation is not a guarantee that every
application refreshes immediately. The timeout applies per recipient window,
not to the whole broadcast. No Explorer termination or sign-out.

## Black desktop without replacing wallpaper files

[IDesktopWallpaper::Enable](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-idesktopwallpaper-enable)
documents that disabling background imagery displays a solid color, set with
[SetBackgroundColor](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-idesktopwallpaper-setbackgroundcolor).
COLORREF zero is RGB black. These are Windows 8+ desktop APIs. Negative
HRESULTs fail; S_FALSE (already requested Enable state) is successful.

The engine manages two independent synthetic state targets, background color
and `ImageVisible`. They are API state, not registry key paths. It never uses
slideshow [GetStatus](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-idesktopwallpaper-getstatus)
as a wallpaper-enable flag: the documented flags describe slideshow state.

Instead, enumerate all monitors and use per-monitor
[GetWallpaper](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-idesktopwallpaper-getwallpaper).
Microsoft states this is empty when no image is displayed or the monitor shows
a solid color. Any successfully returned nonempty path is positive evidence
of visible imagery. Return zero only after every monitor query succeeds and is
empty. Detached monitor assignments are excluded using GetMonitorRECT's S_FALSE
result; at least one attached display is required. Errors or zero attached
monitors are unknown/unsupported, not already-black. Ambiguous per-monitor
GetWallpaper statuses also fail rather than assuming no image.
Do not call GetWallpaper(NULL): it is ambiguous for per-monitor/slideshow cases.

If every monitor is already solid, ImageVisible is unchanged; the module does
not call Enable and therefore need not infer the unknown underlying enable
flag. If at least one image is displayed, capture ImageVisible=1 before
Enable(false); Undo can re-enable the background that this Apply disabled.
Color is a separate transaction action, so partial API failure can be rolled
back independently. Original wallpaper/slideshow source configuration is left
to Windows; it is not copied into action manifests or public output.

The API documentation does not promise to change Spotlight's selected source,
stop Spotlight image acquisition, or preserve slideshow position/timing.
SetWallpaper/SetSlideshow re-enable background imagery. Managed-state drift
guards cannot detect an unrelated latent source change while imagery stays
disabled, and Undo does not overwrite those source paths. Missing original
files, disconnected displays, remote-session suppression and native errors may
require review. These are functional limits, not grounds to bypass the shell.

## Source provenance and acceptance

Interface IID/CLSID, vtable order and detached-monitor semantics were reviewed
against the [Microsoft SDK IDL at commit 0f012441d654d3bb7de898fdc664b5fcad52bdcc](https://github.com/microsoft/win32metadata/blob/0f012441d654d3bb7de898fdc664b5fcad52bdcc/generation/WinSDK/RecompiledIdlHeaders/um/ShObjIdl_core.idl).
Interface signatures were also reviewed against Microsoft's version-pinned
[Windows bindings 0.62.2](https://microsoft.github.io/windows-docs-rs/doc/windows/Win32/UI/Shell/struct.IDesktopWallpaper.html),
alongside the Microsoft Learn method documentation. Interop declarations are
limited to those public API signatures; no third-party theme binaries or
runtime downloads are used. Native HRESULTs and returned string lifetimes must
be handled explicitly.

The benefit is a coherent dark desktop with less visual clutter. Apply/Undo
needs the normal Explorer user and an accessible private journal location;
it does not require elevation. Registry journal confidentiality and exact
rollback remain the existing transaction engine's responsibility.
Portable tests and exact VM acceptance results must be reported separately.
