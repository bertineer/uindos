# Share app suggestions research

## Scope and proposed handling

The target is the current-user Settings preference **System > Share > Show me
suggested apps in share surfaces** on Windows 11 Pro 26H2, build 26300.9711.
The observed starting value was On. The proposed change is to switch it Off in
Settings, reducing optional app suggestions in Share surfaces. This is a
manual preference, not an all-user default, policy enforcement, or prevention
of later app installation or suggestions elsewhere. RAM and network effects
are unknown and are not claimed.

Microsoft describes the feature as app discovery and installation in the Share
window for users signed in with a work or school account. Account context may
therefore affect whether suggestions appear and whether the change has an
observable effect. The native toggle is the only proposed Pro procedure.

## Policy and mapping limits

Microsoft's Experience Policy CSP documents `DisableShareAppPromotions` as a
device policy for Windows 11 24H2 and later, but lists Windows Pro as
unsupported; Enterprise, Education, and IoT Enterprise editions are listed as
supported. Do not deploy that enterprise policy as a Pro setting.

The local `Sharing.admx` includes the same policy name and maps it to
`HKLM\Software\Policies\Microsoft\Windows\ShareSheet\DisableShareAppPromotions`
as a machine DWORD. The local file's SHA-256 is
`D7573CC7A0AFAC901870B4607DC684635116D0545A7D8BD59C49492F00EA0E83`. This
corroborates the policy name and machine mapping; it does not override the
official Pro applicability limit or establish a mapping for the user toggle.
No supported per-user registry mapping for the observed toggle has been
established. Do not infer the legacy `ShowShareProviders` mapping applies.

## Procedure and validation

Use Settings > System > Share and switch **Show me suggested apps in share
surfaces** to Off. Roll back to the previously observed On value only if the
user has not changed it since application. No registry command or production
adapter is proposed.

On Windows 11 Pro 26H2 build 26300.9711, a normal-user observer verified the
same Explorer user/session and captured the initial On state. Native Apply to
Off, unchanged repeat, restoration to On and final Off passed. Closing and
reopening Settings retained Off. Exact UI choices and screenshots remain in
private journals; this is not a claim of exact backing-registry reconstruction.
The local account did not provide work/school app-discovery acceptance. Later
reboot/update persistence and resource/network effects remain unverified.

## Sources

- [Microsoft Support: August 27, 2026 update for Windows 11 24H2/25H2 (KB5120998)](https://support.microsoft.com/en-us/servicing/os/windows-11/2026/08/kb5120998-windows-11-24h2-25h2-update) — feature description and Settings toggle.
- [Microsoft Learn: Experience Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#disableshareapppromotions) — policy scope, edition support, and effect.
