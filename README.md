# HiDPI-Toggle

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6" />
  &nbsp;
  <img src="https://img.shields.io/badge/SwiftUI-Menu%20Bar-0A84FF?style=for-the-badge&logo=apple&logoColor=white" alt="SwiftUI Menu Bar" />
  &nbsp;
  <img src="https://img.shields.io/badge/Apple%20Silicon-M1%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Apple Silicon" />
  &nbsp;
  <img src="https://img.shields.io/badge/open%20source-MIT-34C759?style=for-the-badge" alt="Open source" />
</p>

<p align="center">
  <a href="https://github.com/nipunyatawara-dev/HiDPI-Toggle/releases/latest/download/HiDPIToggle-v2.0.dmg">
    <img src="https://img.shields.io/badge/Download%20for-macOS%20%28Apple%20Silicon%29-0A84FF?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS (Apple Silicon)" />
  </a>
</p>


[**HiDPI Toggle**](https://github.com/nipunyatawara-dev/HiDPI-Toggle) is a tiny macOS menu bar app for controlling external displays. Toggle HiDPI (Retina scaling), choose a resolution, and change the refresh rate without opening System Settings.

* One-click HiDPI toggle per external display from the menu bar
* Resolution picker for each connected external display
* Refresh-rate picker for the selected resolution and HiDPI mode
* Direct mode switching — no virtual displays or mirroring
* Shows resolution, refresh rate, and current HiDPI state for each monitor
* Auto-refreshes when displays are connected or disconnected
* Launch at Login via `SMAppService` (visible in System Settings → Login Items)
* Built with SwiftPM — no Xcode project required

## What's new in version 2

* Change the resolution of each connected external monitor
* Change the refresh rate for the current resolution and HiDPI mode
* Preserve the current refresh rate when changing resolution whenever supported
* Restored the app icon in the application bundle and DMG

See [CHANGELOG.md](CHANGELOG.md) for the version 2 release notes and installation instructions.

# Contents <!-- omit in toc -->

- [What's new in version 2](#whats-new-in-version-2)
- [What HiDPI Toggle is and isn't](#what-hidpi-toggle-is-and-isnt)
- [Menu bar panel](#menu-bar-panel)
- [How it works](#how-it-works)
- [Launch at login](#launch-at-login)
- [Download](#download)
- [Build & run](#build--run)
- [Tech stack](#tech-stack)
- [Limitations](#limitations)
- [Contributing](#contributing)

<a name="about"></a>

# What HiDPI Toggle is and isn't

* **HiDPI Toggle is** a free, open-source utility for controlling HiDPI scaling, resolution, and refresh rate on external monitors. It unlocks hidden Retina scaling modes macOS already knows about but does not expose in System Settings.

* **HiDPI Toggle is not** a full BetterDisplay replacement. It does not manage brightness, color profiles, virtual screens, DDC/CI, or display arrangements.

<a name="panel"></a>

# Menu bar panel

![](assets/01-menu-bar.png)

Click the sparkle-TV icon in the menu bar to open the panel.

* Each connected **external** monitor appears as a card with its name, resolution, and refresh rate
* Choose a supported resolution from the **Resolution** menu
* Choose a supported refresh rate from the **Refresh Rate** menu
* Flip the switch to enable or disable HiDPI for that display
* Displays without a HiDPI variant at the current resolution show **HiDPI unavailable** and the switch is disabled
* Errors (mode read failures, unsupported displays) appear inline in red
* **Launch at Login** keeps the app running after reboot
* **Quit HiDPI Toggle** exits the app — the selected display modes stay in place for the session

The app lives in the menu bar only (`LSUIElement`); there is no Dock icon.

<a name="how"></a>

# How it works

macOS hides the HiDPI ("Retina") variants of an external monitor's resolutions from the public API and the Displays settings panel, but WindowServer keeps them in its internal mode list.

HiDPI Toggle uses private CGS calls to read and switch display modes:

* `CGSGetDisplayModeDescriptionOfLength` — reads the full mode list
* `CGSConfigureDisplayMode` — switches resolutions or selects the hidden "same resolution, density 2.0" mode in place

The resolution menu lists the modes available at the current display density and
tries to preserve the current refresh rate when switching. For HiDPI modes, the
GPU renders at 2× and downscales, so text and UI look much sharper at the same
logical resolution. The refresh-rate menu lists the rates available for the
current resolution and density. Turning the switch off selects the density 1.0
mode again.

The `probe/` folder contains the small research tools used to discover these hidden modes:

* `probe.m` — dumps the WindowServer mode list for a display
* `toggle_test.m` — switches modes from the command line
* `icon_gen.swift` — generates `Icon.icns` from `icon-src.png`

<a name="login"></a>

# Launch at login

The panel includes a **Launch at Login** switch backed by `SMAppService`. Enabling it registers the app as a login item (visible under **System Settings → General → Login Items**).

Registration points at the app's current location on disk. If you move `HiDPIToggle.app` to a new folder, open the panel and re-enable the switch from the new location.

<a name="download"></a>

# Download

Pre-built releases are available on the [Releases](https://github.com/nipunyatawara-dev/HiDPI-Toggle/releases) page.

HiDPIToggle is ad-hoc signed, but it is not signed or notarized with an Apple Developer ID.

1. Download `HiDPIToggle-v2.0.dmg`.
2. Open the DMG and drag **HiDPIToggle** to **Applications**.
3. Run this command **once** in Terminal:

   ```bash
   xattr -cr /Applications/HiDPIToggle.app
   ```

   Alternatively, try to open the app, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

4. Connect an external monitor, click the sparkle-TV icon in the menu bar, and choose the desired HiDPI, resolution, and refresh-rate settings.

**Requirements:** macOS 14 (Sonoma) or later · Apple Silicon (M1 or later) · External monitor

<a name="build"></a>

# Build & run

### Prerequisites

* macOS 14 (Sonoma) or later
* Apple Silicon Mac (M1, M2, M3, M4, or later) — Intel Macs are not supported
* Xcode Command Line Tools (Swift 6)

```bash
xcode-select --install   # if you have not already
```

### Steps

1. Clone the repository:

   ```bash
   git clone https://github.com/nipunyatawara-dev/HiDPI-Toggle.git
   cd HiDPI-Toggle
   ```

2. Build a release `.app` bundle:

   ```bash
   APP_NAME=HiDPIToggle BUNDLE_ID=com.local.hidpitoggle MENU_BAR_APP=1 \
     Scripts/package_app.sh release
   ```

3. Open the app:

   ```bash
   open HiDPIToggle.app
   ```

   The sparkle-TV icon appears in the menu bar. Connect an external monitor, click the icon, and choose the desired HiDPI, resolution, and refresh-rate settings.

### Debug build (terminal only)

```bash
swift build
.build/debug/HiDPIToggle
```

### App icon

When `Icon.icns` is missing, `Scripts/package_app.sh` generates it automatically
from `icon-src.png` and bundles it with the app. To regenerate it manually:

```bash
swift probe/icon_gen.swift icon-src.png Icon.iconset
iconutil --convert icns --output Icon.icns Icon.iconset
```

# Tech stack

| Layer | Technology |
| --- | --- |
| **Language** | Swift 6 |
| **UI** | SwiftUI (`MenuBarExtra`, `.menuBarExtraStyle(.window)`) |
| **Display APIs** | CoreGraphics + private CGS bindings (`CGSPrivate` target) |
| **Login item** | ServiceManagement (`SMAppService`) |
| **Packaging** | SwiftPM + `Scripts/package_app.sh` (no `.xcodeproj`) |
| **Minimum OS** | macOS 14.0 |

<a name="limitations"></a>

# Limitations

* **External displays only** — the built-in Mac display is filtered out
* **Private APIs** — CGS mode-switch functions are undocumented Apple APIs; this app is not App Store–eligible (same situation as BetterDisplay for this feature)
* **Session persistence** — resolution, refresh-rate, and HiDPI changes last for the current session; quitting the app does not revert them
* **Hardware dependent** — available resolutions, refresh rates, and HiDPI variants depend on the monitor and connection; unsupported choices are not shown
* **Ad-hoc signing** — the build script signs with an ad-hoc identity (`-`). For distribution outside your machine you may need to adjust signing or allow the app in **Privacy & Security**

<a name="contributing"></a>

# Contributing

Pull requests and issue reports are welcome.

1. Fork the repo and create a feature branch
2. Make your changes and verify the app still builds:

   ```bash
   APP_NAME=HiDPIToggle BUNDLE_ID=com.local.hidpitoggle MENU_BAR_APP=1 \
     Scripts/package_app.sh release
   ```

3. Open a pull request with a clear description of what changed and why

---

<p align="center">
  <img src="./assets/icon.png" width="80" alt="HiDPI Toggle icon">
</p>
