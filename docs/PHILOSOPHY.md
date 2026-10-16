# Philosophy and boundaries

> Windows, on your terms.

## What uindos is

A publicly shared **personal Windows setup**, not a general-purpose customization platform. Its author selects defaults based on practical privacy, minimalism, performance and a coherent keyboard-first desktop experience. Users may fork or change config files, but upstream need not support every preference.

The name **uindos** is inspired by the Japanese pronunciation of Windows (ウィンドウズ, *uindōzu*). The project is independent of Microsoft and Omarchy.

## Priorities, in order

1. Maintain security, data integrity, recovery and Windows Update compatibility.
2. Minimize avoidable Microsoft data collection, targeted advertising and unwanted consumer experiences.
3. Remove unnecessary installed/provisioned apps and background work.
4. Build a consistent keyboard-first tiling desktop with curated apps.
5. Pursue measurable performance and footprint improvements; avoid folklore.
6. Keep the install small, auditable and straightforward to maintain.

## Intentional defaults

- Target Microsoft Edge **browser** removal and leave WebView2 Runtime available to other apps.
- Remove Copilot and unwanted AI/advertising experiences; check for reappearance after updates.
- Keep Windows Defender, UAC, Windows SmartScreen for downloaded apps, BitLocker, Secure Boot and update infrastructure by default. Their security/privacy tradeoffs must be explicit.
- Prefer Alacritty, Ungoogled Chromium, a tiling manager and one launcher, not multiple competing tools.
- Keep Explorer's underlying shell and a clear fallback desktop even if the custom top bar or tiling app fails.

## Explicit non-goals

- Becoming WinUtil or Win11Debloat, offering endless presets or a general application catalog.
- Supporting every Windows version/edition/device out of the gate.
- Breaking Microsoft services to claim zero Windows egress.
- Trading away security just to save a few MB of memory.
- Removing Windows internals with undocumented filesystem deletion.
- Bundling arbitrary unmaintained software or unsupported licensing workarounds.
- Providing commercial support, enterprise compliance guarantees or a modified Microsoft ISO download.

## Definition of success

A repeatable Windows 11 installation with demonstrably fewer unwanted apps and nonessential integrations, a cohesive Omarchy-like workflow, reliable updates, security intact, and clear reports of both achievements and limits.
