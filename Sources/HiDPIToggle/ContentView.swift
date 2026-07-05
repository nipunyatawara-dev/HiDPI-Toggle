import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: DisplayManager
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if manager.displays.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No external displays connected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(manager.displays) { display in
                    DisplayRow(display: display) { enabled in
                        manager.setHiDPI(enabled, for: display.id)
                    }
                }
            }

            if let error = manager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }

            Divider()

            HStack {
                Label("Launch at Login", systemImage: "power")
                    .font(.system(size: 13))
                Spacer()
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)

            if let error = launchAtLogin.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit HiDPI Toggle", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct DisplayRow: View {
    let display: ExternalDisplay
    let onToggle: (Bool) -> Void

    private var subtitle: String {
        var text = "\(display.width)×\(display.height)  ·  \(display.refreshRate) Hz"
        if display.hiDPIEnabled {
            text += "  ·  HiDPI"
        } else if !display.hiDPIAvailable {
            text += "  ·  HiDPI unavailable"
        }
        return text
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "display")
                .font(.title3)
                .foregroundStyle(display.hiDPIEnabled ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("HiDPI", isOn: Binding(
                get: { display.hiDPIEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!display.hiDPIAvailable)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
