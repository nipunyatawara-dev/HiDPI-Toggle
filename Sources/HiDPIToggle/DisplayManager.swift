import AppKit
import CoreGraphics
import CGSPrivate

struct DisplayResolution: Identifiable, Hashable {
    let width: Int
    let height: Int

    var id: String {
        "\(width)x\(height)"
    }

    var label: String {
        "\(width) × \(height)"
    }
}

struct DisplayRefreshRate: Identifiable, Hashable {
    let hertz: Int

    var id: Int {
        hertz
    }

    var label: String {
        hertz == 0 ? "Variable" : "\(hertz) Hz"
    }
}

struct ExternalDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    let refreshRate: Int
    let availableResolutions: [DisplayResolution]
    let availableRefreshRates: [DisplayRefreshRate]
    var hiDPIEnabled: Bool
    var hiDPIAvailable: Bool

    var currentResolutionID: DisplayResolution.ID {
        DisplayResolution(width: width, height: height).id
    }

    var currentRefreshRateID: DisplayRefreshRate.ID {
        refreshRate
    }

    var refreshRateLabel: String {
        DisplayRefreshRate(hertz: refreshRate).label
    }
}

// Stub/safe-mode entries in the WindowServer mode list; never switch to these.
private let safeModeFlag: UInt32 = 0x4000_0000

@MainActor
final class DisplayManager: ObservableObject {
    @Published var displays: [ExternalDisplay] = []
    @Published var lastError: String?

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.refresh()
            }
        }
    }

    func refresh() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)

        displays = ids.prefix(Int(count)).compactMap { id in
            guard CGDisplayIsBuiltin(id) == 0 else { return nil }
            guard let current = currentMode(of: id) else { return nil }
            let counterpart = matchingMode(
                on: id,
                like: current,
                density: current.density == 2.0 ? 1.0 : 2.0
            )
            return ExternalDisplay(
                id: id,
                name: displayName(for: id),
                width: Int(current.width),
                height: Int(current.height),
                refreshRate: Int(current.freq),
                availableResolutions: availableResolutions(on: id, density: current.density),
                availableRefreshRates: availableRefreshRates(on: id, like: current),
                hiDPIEnabled: current.density == 2.0,
                hiDPIAvailable: current.density == 2.0 || counterpart != nil
            )
        }
    }

    func setHiDPI(_ enabled: Bool, for displayID: CGDirectDisplayID) {
        lastError = nil
        defer { refresh() }

        guard let current = currentMode(of: displayID) else {
            lastError = "Could not read the current display mode."
            return
        }
        let targetDensity: Float = enabled ? 2.0 : 1.0
        guard current.density != targetDensity else { return }

        guard let target = matchingMode(on: displayID, like: current, density: targetDensity) else {
            lastError = "This display has no HiDPI variant of its current resolution."
            return
        }

        apply(target, to: displayID)
    }

    func setRefreshRate(_ refreshRate: DisplayRefreshRate, for displayID: CGDirectDisplayID) {
        lastError = nil
        defer { refresh() }

        guard let current = currentMode(of: displayID) else {
            lastError = "Could not read the current display mode."
            return
        }
        guard let targetFrequency = UInt16(exactly: refreshRate.hertz) else {
            lastError = "The selected refresh rate is invalid."
            return
        }
        guard current.freq != targetFrequency else {
            return
        }

        let candidates = allModes(of: displayID).filter {
            $0.flags & safeModeFlag == 0
                && $0.width == current.width
                && $0.height == current.height
                && $0.density == current.density
                && $0.freq == targetFrequency
        }
        guard let target = candidates.first else {
            lastError = "This refresh rate is not available for the current resolution and HiDPI setting."
            return
        }

        apply(target, to: displayID)
    }

    func setResolution(_ resolution: DisplayResolution, for displayID: CGDirectDisplayID) {
        lastError = nil
        defer { refresh() }

        guard let current = currentMode(of: displayID) else {
            lastError = "Could not read the current display mode."
            return
        }
        guard current.width != resolution.width || current.height != resolution.height else {
            return
        }

        let candidates = allModes(of: displayID).filter {
            $0.flags & safeModeFlag == 0
                && $0.width == resolution.width
                && $0.height == resolution.height
                && $0.density == current.density
        }
        guard let target = candidates.first(where: { $0.freq == current.freq })
            ?? candidates.first else {
            lastError = "This resolution is not available for the display's current HiDPI setting."
            return
        }

        apply(target, to: displayID)
    }

    private func apply(_ target: ModeInfo, to displayID: CGDirectDisplayID) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            lastError = "Could not start display configuration."
            return
        }
        let err = CGSConfigureDisplayMode(config, displayID, Int32(target.index))
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            lastError = "Mode switch failed (error \(err.rawValue))."
            return
        }
        let completionError = CGCompleteDisplayConfiguration(config, .forSession)
        if completionError != .success {
            lastError = "Could not complete the display configuration (error \(completionError.rawValue))."
        }
    }

    // MARK: - WindowServer mode list

    private struct ModeInfo {
        let index: Int
        let width: UInt32
        let height: UInt32
        let freq: UInt16
        let density: Float
        let flags: UInt32
    }

    private func allModes(of displayID: CGDirectDisplayID) -> [ModeInfo] {
        var count: Int32 = 0
        CGSGetNumberOfDisplayModes(displayID, &count)
        return (0..<Int(count)).map { index in
            var mode = CGSDisplayModeDescription()
            CGSGetDisplayModeDescriptionOfLength(
                displayID, Int32(index), &mode,
                Int32(MemoryLayout<CGSDisplayModeDescription>.size)
            )
            return ModeInfo(
                index: index,
                width: mode.width,
                height: mode.height,
                freq: mode.freq,
                density: mode.density,
                flags: mode.flags
            )
        }
    }

    private func currentMode(of displayID: CGDirectDisplayID) -> ModeInfo? {
        var currentIndex: Int32 = -1
        CGSGetCurrentDisplayMode(displayID, &currentIndex)
        let modes = allModes(of: displayID)
        guard currentIndex >= 0, Int(currentIndex) < modes.count else { return nil }
        return modes[Int(currentIndex)]
    }

    private func availableResolutions(
        on displayID: CGDirectDisplayID,
        density: Float
    ) -> [DisplayResolution] {
        let resolutions = allModes(of: displayID).compactMap { mode -> DisplayResolution? in
            guard mode.flags & safeModeFlag == 0, mode.density == density else {
                return nil
            }
            return DisplayResolution(width: Int(mode.width), height: Int(mode.height))
        }

        return Array(Set(resolutions)).sorted {
            let leftArea = $0.width * $0.height
            let rightArea = $1.width * $1.height
            if leftArea != rightArea {
                return leftArea > rightArea
            }
            if $0.width != $1.width {
                return $0.width > $1.width
            }
            return $0.height > $1.height
        }
    }

    private func availableRefreshRates(
        on displayID: CGDirectDisplayID,
        like current: ModeInfo
    ) -> [DisplayRefreshRate] {
        let refreshRates = allModes(of: displayID).compactMap { mode -> DisplayRefreshRate? in
            guard mode.flags & safeModeFlag == 0,
                  mode.width == current.width,
                  mode.height == current.height,
                  mode.density == current.density else {
                return nil
            }
            return DisplayRefreshRate(hertz: Int(mode.freq))
        }

        return Array(Set(refreshRates)).sorted { $0.hertz > $1.hertz }
    }

    /// Finds the mode with the same logical resolution and refresh rate as
    /// `reference` but the requested density.
    private func matchingMode(
        on displayID: CGDirectDisplayID,
        like reference: ModeInfo,
        density: Float
    ) -> ModeInfo? {
        let candidates = allModes(of: displayID).filter {
            $0.flags & safeModeFlag == 0
                && $0.width == reference.width
                && $0.height == reference.height
                && $0.density == density
        }
        return candidates.first { $0.freq == reference.freq } ?? candidates.first
    }

    private func displayName(for displayID: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let number = screen.deviceDescription[key] as? NSNumber,
               number.uint32Value == displayID {
                return screen.localizedName
            }
        }
        return "Display \(displayID)"
    }
}
