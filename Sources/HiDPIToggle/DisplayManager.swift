import AppKit
import CGSPrivate
import CoreGraphics

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

enum DisplayBrightnessControl: Equatable {
    case hardware(maximum: UInt16)
    case software
}

enum DisplayBrightnessStatus: Equatable {
    case checking
    case available(value: Double, control: DisplayBrightnessControl)
    case unavailable
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
    var brightness: DisplayBrightnessStatus

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

private final class NotificationObserverToken: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

private struct SoftwareTransferFormula: Sendable {
    let redMin: CGGammaValue
    let redMax: CGGammaValue
    let redGamma: CGGammaValue
    let greenMin: CGGammaValue
    let greenMax: CGGammaValue
    let greenGamma: CGGammaValue
    let blueMin: CGGammaValue
    let blueMax: CGGammaValue
    let blueGamma: CGGammaValue

    func apply(to displayID: CGDirectDisplayID, brightness: Double) -> CGError {
        let scale = CGGammaValue(min(max(brightness, 0), 1))
        return CGSetDisplayTransferByFormula(
            displayID,
            redMin * scale, redMax * scale, redGamma,
            greenMin * scale, greenMax * scale, greenGamma,
            blueMin * scale, blueMax * scale, blueGamma
        )
    }
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published var displays: [ExternalDisplay] = []
    @Published var lastError: String?

    private var screenParametersObserver: NotificationObserverToken?
    private var terminationObserver: NotificationObserverToken?
    private var screenRefreshTask: Task<Void, Never>?
    private var brightnessProbeTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var brightnessWriteTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var originalTransferFormulas: [CGDirectDisplayID: SoftwareTransferFormula] = [:]
    private var softwareDimmedDisplays: Set<CGDirectDisplayID> = []

    init() {
        refresh()
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
        screenParametersObserver = NotificationObserverToken(observer)

        let terminationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreSoftwareBrightness()
            }
        }
        terminationObserver = NotificationObserverToken(terminationToken)
    }

    func refresh() {
        let previousDisplays = Dictionary(
            uniqueKeysWithValues: displays.map { ($0.id, $0) }
        )
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)

        displays = ids.prefix(Int(count)).compactMap { id in
            guard CGDisplayIsBuiltin(id) == 0 else { return nil }
            let modes = allModes(of: id)
            guard let current = currentMode(of: id, in: modes) else { return nil }
            let counterpart = matchingMode(
                in: modes,
                like: current,
                density: current.density == 2.0 ? 1.0 : 2.0
            )
            return ExternalDisplay(
                id: id,
                name: displayName(for: id),
                width: Int(current.width),
                height: Int(current.height),
                refreshRate: Int(current.freq),
                availableResolutions: availableResolutions(
                    in: modes,
                    density: current.density
                ),
                availableRefreshRates: availableRefreshRates(in: modes, like: current),
                hiDPIEnabled: current.density == 2.0,
                hiDPIAvailable: current.density == 2.0 || counterpart != nil,
                brightness: previousDisplays[id]?.brightness ?? .checking
            )
        }

        let connectedIDs = Set(displays.map(\.id))
        for displayID in Set(brightnessProbeTasks.keys).subtracting(connectedIDs) {
            brightnessProbeTasks.removeValue(forKey: displayID)?.cancel()
        }
        for displayID in Set(brightnessWriteTasks.keys).subtracting(connectedIDs) {
            brightnessWriteTasks.removeValue(forKey: displayID)?.cancel()
        }
        originalTransferFormulas = originalTransferFormulas.filter {
            connectedIDs.contains($0.key)
        }
        softwareDimmedDisplays.formIntersection(connectedIDs)

        for display in displays {
            switch display.brightness {
            case .checking:
                probeBrightness(for: display.id)
            case .available(let value, .software) where value < 0.999:
                scheduleSoftwareBrightness(value, for: display.id)
            default:
                break
            }
        }
    }

    func setHiDPI(_ enabled: Bool, for displayID: CGDirectDisplayID) {
        lastError = nil
        defer { refresh() }

        let modes = allModes(of: displayID)
        guard let current = currentMode(of: displayID, in: modes) else {
            lastError = "Could not read the current display mode."
            return
        }
        let targetDensity: Float = enabled ? 2.0 : 1.0
        guard current.density != targetDensity else { return }

        guard let target = matchingMode(in: modes, like: current, density: targetDensity) else {
            lastError = "This display has no HiDPI variant of its current resolution."
            return
        }

        apply(target, to: displayID)
    }

    func setRefreshRate(_ refreshRate: DisplayRefreshRate, for displayID: CGDirectDisplayID) {
        lastError = nil
        defer { refresh() }

        let modes = allModes(of: displayID)
        guard let current = currentMode(of: displayID, in: modes) else {
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

        let candidates = modes.filter {
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

        let modes = allModes(of: displayID)
        guard let current = currentMode(of: displayID, in: modes) else {
            lastError = "Could not read the current display mode."
            return
        }
        guard current.width != resolution.width || current.height != resolution.height else {
            return
        }

        let candidates = modes.filter {
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

    func setBrightness(_ brightness: Double, for displayID: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }),
              case .available(_, let control) = displays[index].brightness else {
            return
        }

        let normalizedValue = min(max(brightness, 0), 1)
        displays[index].brightness = .available(
            value: normalizedValue,
            control: control
        )
        lastError = nil

        switch control {
        case .hardware(let maximum):
            scheduleHardwareBrightness(
                UInt16((normalizedValue * Double(maximum)).rounded()),
                normalizedValue: normalizedValue,
                for: displayID
            )
        case .software:
            scheduleSoftwareBrightness(normalizedValue, for: displayID)
        }
    }

    private func scheduleHardwareBrightness(
        _ rawValue: UInt16,
        normalizedValue: Double,
        for displayID: CGDirectDisplayID
    ) {
        brightnessWriteTasks[displayID]?.cancel()
        brightnessWriteTasks[displayID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }

            let succeeded = await Task.detached(priority: .userInitiated) {
                HDTDDCWriteBrightness(displayID, rawValue)
            }.value
            guard !Task.isCancelled, let self else { return }

            brightnessWriteTasks[displayID] = nil
            if succeeded {
                UserDefaults.standard.set(
                    normalizedValue,
                    forKey: hardwareBrightnessPreferenceKey(for: displayID)
                )
            } else {
                lastError = "Could not set this display's brightness over DDC/CI."
            }
        }
    }

    private func scheduleSoftwareBrightness(
        _ normalizedValue: Double,
        for displayID: CGDirectDisplayID
    ) {
        guard let formula = originalTransferFormulas[displayID]
            ?? captureTransferFormula(for: displayID) else {
            if let index = displays.firstIndex(where: { $0.id == displayID }) {
                displays[index].brightness = .unavailable
            }
            lastError = "Could not configure software brightness for this display."
            return
        }

        brightnessWriteTasks[displayID]?.cancel()
        brightnessWriteTasks[displayID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }

            let result = await Task.detached(priority: .userInitiated) {
                formula.apply(to: displayID, brightness: normalizedValue).rawValue
            }.value
            guard !Task.isCancelled, let self else { return }

            brightnessWriteTasks[displayID] = nil
            if result == CGError.success.rawValue {
                UserDefaults.standard.set(
                    normalizedValue,
                    forKey: softwareBrightnessPreferenceKey(for: displayID)
                )
                if normalizedValue < 0.999 {
                    softwareDimmedDisplays.insert(displayID)
                } else {
                    softwareDimmedDisplays.remove(displayID)
                }
            } else {
                lastError = "Could not set this display's software brightness."
            }
        }
    }

    private func scheduleRefresh() {
        screenRefreshTask?.cancel()
        screenRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private struct BrightnessProbeResult: Sendable {
        let support: Int32
        let current: UInt16
        let maximum: UInt16
    }

    private func probeBrightness(for displayID: CGDirectDisplayID) {
        guard brightnessProbeTasks[displayID] == nil else { return }

        brightnessProbeTasks[displayID] = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                var current: UInt16 = 0
                var maximum: UInt16 = 0
                let support = HDTDDCProbeBrightness(displayID, &current, &maximum)
                return BrightnessProbeResult(
                    support: support,
                    current: current,
                    maximum: maximum
                )
            }.value
            guard !Task.isCancelled, let self else { return }

            brightnessProbeTasks[displayID] = nil
            guard let index = displays.firstIndex(where: { $0.id == displayID }) else {
                return
            }

            switch result.support {
            case 2 where result.maximum > 0:
                displays[index].brightness = .available(
                    value: Double(result.current) / Double(result.maximum),
                    control: .hardware(maximum: result.maximum)
                )
            default:
                guard captureTransferFormula(for: displayID) != nil else {
                    displays[index].brightness = .unavailable
                    return
                }
                let preferenceKey = softwareBrightnessPreferenceKey(for: displayID)
                let savedValue = UserDefaults.standard.object(forKey: preferenceKey)
                    as? Double ?? 1
                let normalizedValue = min(max(savedValue, 0), 1)
                displays[index].brightness = .available(
                    value: normalizedValue,
                    control: .software
                )
                if normalizedValue < 0.999 {
                    scheduleSoftwareBrightness(normalizedValue, for: displayID)
                }
            }
        }
    }

    private func captureTransferFormula(
        for displayID: CGDirectDisplayID
    ) -> SoftwareTransferFormula? {
        if let existing = originalTransferFormulas[displayID] {
            return existing
        }

        var redMin: CGGammaValue = 0
        var redMax: CGGammaValue = 0
        var redGamma: CGGammaValue = 0
        var greenMin: CGGammaValue = 0
        var greenMax: CGGammaValue = 0
        var greenGamma: CGGammaValue = 0
        var blueMin: CGGammaValue = 0
        var blueMax: CGGammaValue = 0
        var blueGamma: CGGammaValue = 0
        guard CGGetDisplayTransferByFormula(
            displayID,
            &redMin, &redMax, &redGamma,
            &greenMin, &greenMax, &greenGamma,
            &blueMin, &blueMax, &blueGamma
        ) == .success else {
            return nil
        }

        let formula = SoftwareTransferFormula(
            redMin: redMin, redMax: redMax, redGamma: redGamma,
            greenMin: greenMin, greenMax: greenMax, greenGamma: greenGamma,
            blueMin: blueMin, blueMax: blueMax, blueGamma: blueGamma
        )
        originalTransferFormulas[displayID] = formula
        return formula
    }

    private func restoreSoftwareBrightness() {
        brightnessWriteTasks.values.forEach { $0.cancel() }
        for displayID in softwareDimmedDisplays {
            _ = originalTransferFormulas[displayID]?.apply(
                to: displayID,
                brightness: 1
            )
        }
        softwareDimmedDisplays.removeAll()
    }

    private func hardwareBrightnessPreferenceKey(
        for displayID: CGDirectDisplayID
    ) -> String {
        "hardwareBrightness.\(displayPreferenceKey(for: displayID))"
    }

    private func softwareBrightnessPreferenceKey(
        for displayID: CGDirectDisplayID
    ) -> String {
        "softwareBrightness.\(displayPreferenceKey(for: displayID))"
    }

    private func displayPreferenceKey(for displayID: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        return "\(vendor).\(model).\(serial)"
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

    private func currentMode(
        of displayID: CGDirectDisplayID,
        in modes: [ModeInfo]
    ) -> ModeInfo? {
        var currentIndex: Int32 = -1
        CGSGetCurrentDisplayMode(displayID, &currentIndex)
        guard currentIndex >= 0 else { return nil }
        return modes.first { $0.index == Int(currentIndex) }
    }

    private func availableResolutions(
        in modes: [ModeInfo],
        density: Float
    ) -> [DisplayResolution] {
        let resolutions = modes.compactMap { mode -> DisplayResolution? in
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
        in modes: [ModeInfo],
        like current: ModeInfo
    ) -> [DisplayRefreshRate] {
        let refreshRates = modes.compactMap { mode -> DisplayRefreshRate? in
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
        in modes: [ModeInfo],
        like reference: ModeInfo,
        density: Float
    ) -> ModeInfo? {
        let candidates = modes.filter {
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
