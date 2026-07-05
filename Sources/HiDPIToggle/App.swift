import SwiftUI

@main
struct HiDPIToggleApp: App {
    @StateObject private var manager = DisplayManager()
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some Scene {
        MenuBarExtra("HiDPI Toggle", systemImage: "sparkles.tv") {
            ContentView(manager: manager, launchAtLogin: launchAtLogin)
        }
        .menuBarExtraStyle(.window)
    }
}
