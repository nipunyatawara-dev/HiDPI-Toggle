# HiDPIToggle 2.0

### HiDPI scaling, resolution, and refresh-rate controls — from the menu bar

**What's new in version 2**

- Change the resolution of each connected external monitor
- Change the refresh rate for the current resolution and HiDPI mode
- Preserve the current refresh rate when changing resolution whenever supported
- Restored the app icon in the application bundle and DMG

**What it does**

- Toggle HiDPI on or off per external monitor with one switch
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

1. Download `HiDPIToggle-v2.0.dmg`.
2. Open the DMG and drag **HiDPIToggle** to **Applications**.
3. Run this command **once** in Terminal:

   ```bash
   xattr -cr /Applications/HiDPIToggle.app
   ```

   Alternatively, try to open the app, then go to **System Settings → Privacy &
   Security** and click **Open Anyway**.

4. Connect an external monitor, click the sparkle-TV icon in the menu bar, and
   choose the desired HiDPI, resolution, and refresh-rate settings.
