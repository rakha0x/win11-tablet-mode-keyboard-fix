# Windows 11 Tablet Mode Keyboard Fix (2-in-1 keyboard / touchpad not working)

Fix for **Windows 11 keyboard not working / touchpad not working on a
2-in-1 laptop** (HP Pavilion x360, Lenovo Yoga, Surface-style
convertibles) when Windows is **stuck in tablet mode** — even in normal
laptop position. Also includes a **Windows 11 tablet mode on/off toggle**
for the touch-optimized taskbar, since Microsoft removed the old
Windows 10 switch.

## Symptoms this fixes

- Built-in keyboard and touchpad dead on a 2-in-1, external USB ones fine
- `ConvertibleSlateMode` reads `0x0` (tablet) while the lid is in laptop position
- Device Manager > Sensors > **Intel(R) Integrated Sensor Solution**
  shows **Error / Code 22** (device disabled)
- Touch-optimized taskbar appears or misbehaves on a non-tablet PC

Root cause: the posture/orientation sensor is disabled, so Windows
thinks the device is folded and shuts off the internal keyboard as
"anti-ghostpress" behavior. Re-enabling the sensor restores everything.

Note: Newer driver updates may rename the sensor to **HID Sensor Collection V2** (leaving the older Intel entry as a ghost); the tool detects both, and auto-recovers if Explorer locks taskbar registry keys.

## Use (no terminal)

1. Copy these two files to the Windows 11 laptop (same folder, keep names):
   - `Run-Win11-TabletMode-KeyboardFix.bat`
   - `Win11-TabletMode-KeyboardFix.ps1`
2. Double-click **`Run-Win11-TabletMode-KeyboardFix.bat`**
   (not the `.ps1` — Windows opens `.ps1` in Notepad by design).
3. The window shows live status:
   - **Sensor** — OK vs Error (Intel Integrated Sensor Solution)
   - **Windows posture** — LAPTOP vs TABLET (`ConvertibleSlateMode`)
   - **Taskbar** — AUTO vs forced TABLET/DESKTOP
4. Press a button:
   - **Fix Keyboard (enable sensor)** — re-enables the disabled sensor.
     Requires admin; the tool offers to relaunch itself as admin.
   - **Tablet ON / OFF / Auto** — forces or releases the touch-optimized
     taskbar. No admin needed. Confirms an Explorer restart so it applies
     instantly (taskbar flickers briefly — normal).
   - **EC Reset Guide (needs physical power-hold)** — automates the software
     half of an Embedded Controller reset by scheduling a full shutdown
     (30-second countdown, bypassing Windows Fast Startup; cancel anytime
     with `shutdown /a`) and logs the physical steps you must do by hand:
     unplug charger and all USB devices after the screen goes dark, hold
     the physical power button for 15–20 seconds to drain residual power,
     replug, power on, and re-check posture. No admin needed.
   - **Copy Diagnostics** — gathers system and hardware state (Windows OS
     caption/build, admin privilege, sensor status with problem codes, raw
     `ConvertibleSlateMode` + taskbar registry values, keyboard devices, and
     GPIO/Lid controllers) and exports it both to the Windows clipboard and to
     a desktop text file (`%USERPROFILE%\Desktop\TabletFix-Diag.txt`)
     so you can easily paste or attach it for remote diagnosis. No admin needed.
   - **Force Laptop Mode (no tablet)** -- for users who never use tablet mode:
     disables slate-reporting sensors and forces `ConvertibleSlateMode` to `1`
     (laptop posture) so the keyboard stays active. Offers an immediate reboot
     (30-second timer, cancelable with `shutdown /a`) to finalize driver state.
     Requires admin; the tool offers to relaunch itself as admin. Reversible
     at any time via the **Fix Keyboard** button. Honest limit: if the
     firmware/EC keeps reporting tablet, Windows resets slate to `0` at boot
     and this cannot help -- update BIOS/drivers or service the hinge sensor.

In File Explorer, turn on `View > Show > File name extensions` to make
sure the launcher is really
`Run-Win11-TabletMode-KeyboardFix.bat`, not
`...bat.txt` (a common copy/download mishap).

## Manual diagnosis (what the GUI does for you)

```powershell
# 1. Sensor state — expect OK; Error means this tool's Fix button applies
Get-PnpDevice -FriendlyName *Intel*Sensor* | Select FriendlyName,Status
# 2. Problem code — 22 = disabled (one click to fix), 10 = broken driver
Get-PnpDevice -FriendlyName *Intel*Sensor* | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_ProblemCode | Select DeviceId,Data
# 3. Posture — 0x0 = tablet (keyboard killed), 0x1 = laptop (normal)
reg query HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl /v ConvertibleSlateMode
```

Real case (HP Pavilion x360 14-dh1053tx): Code **22**, slate **0x0**.
One `Enable-PnpDevice` (as admin) → sensor OK, slate `0x1`, keyboard
alive. If the code is **10**, clean-reinstall the driver instead:
Device Manager > Uninstall device > reboot > Action > Scan for hardware
changes, or install the Chipset/ISH driver from your vendor's support
page. Last resorts: EC reset (shutdown, unplug everything, hold power
15–20 s) and a BIOS update (battery above 50%).

## Keywords

windows 11 tablet mode, tablet mode on off windows 11, windows 11
keyboard not working 2 in 1, hp pavilion x360 keyboard not working,
lenovo yoga keyboard disabled tablet mode, intel integrated sensor
solution code 22, convertibleslatemode 0 keyboard dead, touch taskbar
force windows 11, enable-pnpdevice sensor fix

## Honest limitations

- Not a full Windows 10-style tablet mode — Microsoft removed that.
  The taskbar buttons force only the touch-optimized taskbar
  (collapsed/expanded states).
- The Fix button covers the disabled-sensor case (Code 22). Broken or
  mismatched drivers (Code 10+) still need a vendor driver install.
- Written from a Mac; GUI smoke test on real Windows 11 pending.
  If the log box shows red, screenshot it and open an issue.

## Files

| File | What it is |
|---|---|
| `Run-Win11-TabletMode-KeyboardFix.bat` | Double-click launcher (calls the `.ps1` next to it) |
| `Win11-TabletMode-KeyboardFix.ps1` | The tool: sensor status, keyboard fix, taskbar on/off/auto, EC reset guide, diagnostics export |

References: ElevenForum "Turn On or Off Tablet-optimized Taskbar in
Windows 11", Microsoft Learn `ConvertibleSlateMode`.
