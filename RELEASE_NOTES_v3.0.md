### HiDPI scaling, brightness, resolution, and refresh-rate controls — from the menu bar

**What's new in version 3**

- Change the brightness of each connected external monitor
- Use hardware brightness over DDC/CI when supported by the monitor and connection
- Fall back to low-overhead software dimming when DDC/CI is unavailable
- Move display communication away from the UI thread and coalesce rapid slider changes
- Reduce repeated display scans and coalesce screen-change notifications for lower CPU usage
- Fix display-observer lifetime, DDC reply addressing, and brightness capability detection

**What it does**

- Toggle HiDPI on or off per external monitor with one switch
- Adjust brightness using hardware DDC/CI or software dimming as a fallback
- Choose a supported resolution for each external monitor
- Choose a supported refresh rate for the current resolution and HiDPI mode
- Show the resolution, refresh rate, and current HiDPI state for each display
- Switch display modes without virtual screens or mirroring
- Automatically detect when displays are connected or disconnected
- Optionally launch at login

**Requirements**

- macOS 14 (Sonoma) or later
- Apple Silicon Mac (M1, M2, M3, M4, or later)
- External monitor (the built-in display is not supported)

**Install instructions**

HiDPIToggle is ad-hoc signed, but it is not signed or notarized with an Apple
Developer ID.

1. Download `HiDPIToggle-v3.0.dmg`.
2. Open the DMG and drag **HiDPIToggle** to **Applications**.
3. Run this command **once** in Terminal:

   ```bash
   xattr -cr /Applications/HiDPIToggle.app
   ```

   Alternatively, try to open the app, then go to **System Settings → Privacy &
   Security** and click **Open Anyway**.

4. Connect an external monitor, click the sparkle TV icon in the menu bar, and
   choose the desired brightness, HiDPI, resolution, and refresh-rate settings.

Hardware brightness requires a monitor and connection that pass DDC/CI commands.
When DDC/CI is unavailable, HiDPIToggle visibly dims the display in software
without changing the monitor's physical backlight setting.
