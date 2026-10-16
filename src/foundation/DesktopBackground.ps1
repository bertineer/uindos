# Fixed, per-user desktop background operations using the documented
# IDesktopWallpaper Shell COM interface. No arbitrary wallpaper paths or
# manifest-supplied commands are accepted.

function Get-UindosDesktopBackgroundActionCatalog {
    return @(
        [pscustomobject]@{
            id = 'desktop.background-color'
            path = 'desktop:background'
            name = 'Color'
            kind = 'DWord'
            value = 0
        },
        [pscustomobject]@{
            id = 'desktop.background-image-visible'
            path = 'desktop:background'
            name = 'ImageVisible'
            kind = 'DWord'
            value = 0
        }
    )
}

function Get-UindosDesktopBackgroundActions {
    [CmdletBinding()]
    param()
    return @(Get-UindosDesktopBackgroundActionCatalog)
}

function Assert-UindosDesktopBackgroundAction {
    param([Parameter(Mandatory)]$Action)
    $matching = @(Get-UindosDesktopBackgroundActionCatalog | Where-Object {
        $_.id -ceq [string]$Action.id
    })
    if ($matching.Count -ne 1) {
        throw [System.NotSupportedException]::new('Action ID is not in the fixed desktop background allowlist.')
    }
    $rule = $matching[0]
    if ($rule.path -cne [string]$Action.path -or
        $rule.name -cne [string]$Action.name -or
        $rule.kind -cne [string]$Action.kind -or
        [string]$rule.value -cne [string]$Action.value) {
        throw [System.NotSupportedException]::new('Action differs from the fixed desktop background default.')
    }
}

function Assert-UindosDesktopBackgroundTarget {
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$Name)
    $matching = @(Get-UindosDesktopBackgroundActionCatalog | Where-Object {
        $_.path -ceq $Path -and $_.name -ceq $Name
    })
    if ($matching.Count -ne 1) {
        throw [System.NotSupportedException]::new('Target is outside the desktop background allowlist.')
    }
}

function ConvertTo-UindosDesktopBackgroundDWord {
    param([Parameter(Mandatory)]$Value,
          [Parameter(Mandatory)][string]$Name)
    if ($Value -is [bool] -or $Value -isnot [byte] -and $Value -isnot [sbyte] -and
        $Value -isnot [int16] -and $Value -isnot [uint16] -and
        $Value -isnot [int32] -and $Value -isnot [uint32] -and
        $Value -isnot [int64] -and $Value -isnot [uint64]) {
        throw [System.NotSupportedException]::new("$Name must be an integer value.")
    }
    [long]$number = 0
    if (-not [long]::TryParse([string]$Value, [Globalization.NumberStyles]::None,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        throw [System.NotSupportedException]::new("$Name is outside the supported integer range.")
    }
    $maximum = if ($Name -ceq 'Color') { 16777215L } else { 1L }
    if ($number -lt 0 -or $number -gt $maximum) {
        throw [System.NotSupportedException]::new("$Name is outside the supported desktop background range.")
    }
    return [int]$number
}

function Get-UindosDesktopBackgroundNativeType {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('IDesktopWallpaper is available only on Windows.')
    }
    if ('Uindos.DesktopBackground.NativeApi' -as [type]) { return }

    # Vtable order, IID/CLSID, and monitor semantics are pinned to Microsoft's
    # Win32 metadata SDK IDL at commit 0f012441d654d3bb7de898fdc664b5fcad52bdcc:
    # https://github.com/microsoft/win32metadata/blob/0f012441d654d3bb7de898fdc664b5fcad52bdcc/generation/WinSDK/RecompiledIdlHeaders/um/ShObjIdl_core.idl
    # The projected method signatures also match Microsoft's windows crate
    # 0.62.2 reference. PreserveSig keeps HRESULTs visible so S_FALSE remains
    # a successful result (GetMonitorRECT uses it for detached monitors).
    $source = @'
using System;
using System.Runtime.InteropServices;

namespace Uindos.DesktopBackground
{
    [ComImport]
    [Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IDesktopWallpaper
    {
        [PreserveSig] int SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId,
            [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [PreserveSig] int GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId,
            out IntPtr wallpaper);
        [PreserveSig] int GetMonitorDevicePathAt(uint monitorIndex, out IntPtr monitorId);
        [PreserveSig] int GetMonitorDevicePathCount(out uint count);
        [PreserveSig] int GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorId,
            out RECT displayRect);
        [PreserveSig] int SetBackgroundColor(uint color);
        [PreserveSig] int GetBackgroundColor(out uint color);
        [PreserveSig] int SetPosition(int position);
        [PreserveSig] int GetPosition(out int position);
        [PreserveSig] int SetSlideshow(IntPtr items);
        [PreserveSig] int GetSlideshow(out IntPtr items);
        [PreserveSig] int SetSlideshowOptions(uint options, uint slideshowTick);
        [PreserveSig] int GetSlideshowOptions(out uint options, out uint slideshowTick);
        [PreserveSig] int AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorId,
            int direction);
        [PreserveSig] int GetStatus(out uint state);
        [PreserveSig] int Enable([MarshalAs(UnmanagedType.Bool)] bool enable);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    public sealed class DesktopBackgroundState
    {
        public int Color { get; set; }
        public int ImageVisible { get; set; }
        public int MonitorCount { get; set; }
    }

    public static class NativeApi
    {
        private static readonly Guid DesktopWallpaperClass =
            new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD");

        private static void Check(int hr, string operation)
        {
            if (hr < 0)
            {
                Marshal.ThrowExceptionForHR(hr);
                throw new COMException(operation + " failed.", hr);
            }
        }

        private static IDesktopWallpaper Create()
        {
            Type type = Type.GetTypeFromCLSID(DesktopWallpaperClass, true);
            return (IDesktopWallpaper)Activator.CreateInstance(type);
        }

        public static DesktopBackgroundState Read()
        {
            IDesktopWallpaper wallpaper = null;
            try
            {
                wallpaper = Create();
                uint color;
                Check(wallpaper.GetBackgroundColor(out color), "GetBackgroundColor");

                uint count;
                Check(wallpaper.GetMonitorDevicePathCount(out count), "GetMonitorDevicePathCount");
                if (count == 0)
                    throw new InvalidOperationException("No desktop monitors were returned; refusing an unknown state.");

                bool imageVisible = false;
                uint attachedCount = 0;
                for (uint index = 0; index < count; index++)
                {
                    IntPtr monitorPointer = IntPtr.Zero;
                    try
                    {
                        Check(wallpaper.GetMonitorDevicePathAt(index, out monitorPointer),
                            "GetMonitorDevicePathAt");
                        if (monitorPointer == IntPtr.Zero)
                            throw new InvalidOperationException("Monitor path was null; refusing an unknown state.");
                        string monitorId = Marshal.PtrToStringUni(monitorPointer);
                        if (String.IsNullOrEmpty(monitorId))
                            throw new InvalidOperationException("Monitor path was empty; refusing an unknown state.");

                        RECT displayRect;
                        int monitorStatus = wallpaper.GetMonitorRECT(monitorId, out displayRect);
                        Check(monitorStatus, "GetMonitorRECT");
                        if (monitorStatus == 1) // S_FALSE means this assigned monitor is detached.
                            continue;
                        if (monitorStatus != 0)
                            throw new InvalidOperationException("GetMonitorRECT returned an undocumented status; refusing an unknown monitor state.");
                        attachedCount++;

                        IntPtr imagePointer = IntPtr.Zero;
                        try
                        {
                            int imageStatus = wallpaper.GetWallpaper(monitorId, out imagePointer);
                            Check(imageStatus, "GetWallpaper");
                            if (imageStatus != 0)
                                throw new InvalidOperationException("Per-monitor GetWallpaper returned an ambiguous status; refusing an unknown image state.");
                            if (imagePointer != IntPtr.Zero &&
                                !String.IsNullOrEmpty(Marshal.PtrToStringUni(imagePointer)))
                                imageVisible = true;
                        }
                        finally
                        {
                            if (imagePointer != IntPtr.Zero)
                                Marshal.FreeCoTaskMem(imagePointer);
                        }
                    }
                    finally
                    {
                        if (monitorPointer != IntPtr.Zero)
                            Marshal.FreeCoTaskMem(monitorPointer);
                    }
                }
                if (attachedCount == 0)
                    throw new InvalidOperationException("No attached desktop monitors were returned; refusing an unknown state.");

                return new DesktopBackgroundState {
                    Color = checked((int)color),
                    ImageVisible = imageVisible ? 1 : 0,
                    MonitorCount = checked((int)attachedCount)
                };
            }
            finally
            {
                if (wallpaper != null && Marshal.IsComObject(wallpaper))
                    Marshal.FinalReleaseComObject(wallpaper);
            }
        }

        public static void SetColor(int color)
        {
            if (color < 0 || color > 16777215)
                throw new ArgumentOutOfRangeException("color");
            IDesktopWallpaper wallpaper = null;
            try
            {
                wallpaper = Create();
                Check(wallpaper.SetBackgroundColor((uint)color), "SetBackgroundColor");
            }
            finally
            {
                if (wallpaper != null && Marshal.IsComObject(wallpaper))
                    Marshal.FinalReleaseComObject(wallpaper);
            }
        }

        public static void SetImageVisible(int visible)
        {
            if (visible != 0 && visible != 1)
                throw new ArgumentOutOfRangeException("visible");
            IDesktopWallpaper wallpaper = null;
            try
            {
                wallpaper = Create();
                Check(wallpaper.Enable(visible != 0), "Enable");
            }
            finally
            {
                if (wallpaper != null && Marshal.IsComObject(wallpaper))
                    Marshal.FinalReleaseComObject(wallpaper);
            }
        }
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}

function Get-UindosDesktopBackgroundNativeState {
    Get-UindosDesktopBackgroundNativeType
    return [Uindos.DesktopBackground.NativeApi]::Read()
}

function New-UindosDesktopBackgroundAdapter {
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Backend)

    if ($null -ne $Backend) {
        foreach ($method in @('Read', 'SetColor', 'SetImageVisible')) {
            if (-not $Backend.ContainsKey($method) -or $Backend[$method] -isnot [scriptblock]) {
                throw "Trusted desktop background backend is missing '$method'."
            }
        }
    }
    else {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('IDesktopWallpaper is available only on Windows.')
        }
    }

    $capturedBackend = $Backend
    return @{
        ValidateAction = { param($Action) Assert-UindosDesktopBackgroundAction -Action $Action }.GetNewClosure()
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosDesktopBackgroundTarget -Path $Path -Name $Name
            $state = if ($null -ne $capturedBackend) { & $capturedBackend.Read }
                else { Get-UindosDesktopBackgroundNativeState }
            if ($null -eq $state -or $null -eq $state.PSObject.Properties['Color'] -or
                $null -eq $state.PSObject.Properties['ImageVisible'] -or
                $null -eq $state.PSObject.Properties['MonitorCount']) {
                throw 'Desktop background read did not return a complete state.'
            }
            [int]$monitorCount = 0
            if (-not [int]::TryParse([string]$state.MonitorCount,
                    [Globalization.NumberStyles]::None,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$monitorCount) -or
                $monitorCount -lt 1) {
                throw 'Desktop background monitor count is unknown; refusing to assume no image is visible.'
            }
            $color = ConvertTo-UindosDesktopBackgroundDWord -Value $state.Color -Name 'Color'
            $imageVisible = ConvertTo-UindosDesktopBackgroundDWord -Value $state.ImageVisible -Name 'ImageVisible'
            return [pscustomobject]@{
                exists = $true
                kind = 'DWord'
                value = if ($Name -ceq 'Color') { $color } else { $imageVisible }
            }
        }.GetNewClosure()
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosDesktopBackgroundTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord') { throw 'Desktop background adapter only writes DWORD values.' }
            $number = ConvertTo-UindosDesktopBackgroundDWord -Value $Value -Name $Name
            if ($null -ne $capturedBackend) {
                if ($Name -ceq 'Color') { & $capturedBackend.SetColor $number }
                else { & $capturedBackend.SetImageVisible $number }
            }
            else {
                Get-UindosDesktopBackgroundNativeType
                if ($Name -ceq 'Color') { [Uindos.DesktopBackground.NativeApi]::SetColor($number) }
                else { [Uindos.DesktopBackground.NativeApi]::SetImageVisible($number) }
            }
        }.GetNewClosure()
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosDesktopBackgroundTarget -Path $Path -Name $Name
            throw [System.NotSupportedException]::new('Desktop background API targets always exist; removal is unsupported.')
        }.GetNewClosure()
    }
}
