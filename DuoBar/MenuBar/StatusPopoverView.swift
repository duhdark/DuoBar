import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject private var statusStore: SystemStatusStore
    @AppStorage(PreferenceKeys.showBatteryPercentage) private var showBatteryPercentage = true
    @AppStorage(PreferenceKeys.batteryColorCoding) private var batteryColorCoding = false
    private let onClose: () -> Void

    init(statusStore: SystemStatusStore, onClose: @escaping () -> Void) {
        self.statusStore = statusStore
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("DuoBar")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                DuoGlyphView(
                    status: statusStore.status,
                    metrics: DuoGlyphMetrics.standard.sized(20),
                    animationsEnabled: false,
                    batteryColorCodingEnabled: batteryColorCoding
                )
            }
            .padding(.horizontal, 2)

            Button(action: openNetworkSettings) {
                StatusRow(
                    symbol: networkSymbol,
                    title: localized("Network"),
                    detail: networkDetail,
                    stateText: networkState,
                    tint: .primary,
                    accessory: .disclosure
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityHint(networkSettingsHint)

            VolumeStatusRow(
                volume: statusStore.status.audio.volume,
                hasOutputDevice: statusStore.status.audio.defaultOutput != nil,
                playbackDeviceIdentifier: statusStore.status.audio.defaultOutput?.uid,
                onSetVolume: statusStore.setVolume,
                onSetMuted: statusStore.setMuted
            )

            Button(action: openBatterySettings) {
                StatusRow(
                    symbol: batterySymbol,
                    title: localized("Battery"),
                    detail: batteryDetail,
                    stateText: batteryPercentage,
                    tint: .primary,
                    accessory: .disclosure
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityHint(localized("Open Battery Settings"))

            AudioOutputRow(
                symbol: audioOutputSymbol,
                title: localized("Audio Output"),
                detail: audioOutputDetail,
                stateText: audioOutputState,
                outputs: statusStore.status.audio.selectableOutputs,
                selectedUID: statusStore.status.audio.defaultOutput?.uid,
                onSelect: { statusStore.setDefaultOutput(uid: $0) },
                onOpenSoundSettings: openSoundSettings
            )

            #if DEBUG
            if !MarketingCaptureMode.isEnabled {
                DebugStatusSimulatorView(statusStore: statusStore)
            }
            #endif

            Divider()

            HStack(spacing: 6) {
                settingsAction

                Spacer()

                Button(localized("Quit DuoBar")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 3)
        }
        .padding(12)
        .frame(width: 304)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            statusStore.requestWiFiSSIDAccess()
        }
    }

    @ViewBuilder
    private var settingsAction: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                settingsLabel
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
                onClose()
            })
        } else {
            Button(action: openSettingsFromApplicationMenu) {
                settingsLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsLabel: some View {
        Label(localized("Settings"), systemImage: "gearshape")
    }

    private func openSettingsFromApplicationMenu() {
        NSApp.activate(ignoringOtherApps: true)
        if let settingsItem = findSettingsMenuItem(in: NSApp.mainMenu), let action = settingsItem.action {
            NSApp.sendAction(action, to: settingsItem.target, from: settingsItem)
        }
        onClose()
    }

    private func findSettingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.keyEquivalent == ",", item.keyEquivalentModifierMask.contains(.command) {
                return item
            }
            if let settingsItem = findSettingsMenuItem(in: item.submenu) {
                return settingsItem
            }
        }
        return nil
    }

    private var networkSettingsHint: String {
        SystemSettingsOpener.pane(for: statusStore.status.network) == .network
            ? localized("Open Network Settings")
            : localized("Open Wi-Fi Settings")
    }

    private func openNetworkSettings() {
        _ = SystemSettingsOpener.open(SystemSettingsOpener.pane(for: statusStore.status.network))
        onClose()
    }

    private func openBatterySettings() {
        _ = SystemSettingsOpener.open(.battery)
        onClose()
    }

    private func openSoundSettings() {
        _ = SystemSettingsOpener.open(.sound)
        onClose()
    }

    private var networkSymbol: String {
        let network = statusStore.status.network
        guard network.isConnected else { return "network.slash" }
        switch network.transport {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector.horizontal"
        case .other: return "ellipsis.circle"
        case .none: return "network.slash"
        }
    }

    private var networkDetail: String {
        let network = statusStore.status.network
        guard network.isAvailable else { return localized("No network interface") }
        guard network.isConnected else {
            return network.isWiFiPoweredOn == false ? localized("Wi-Fi disabled") : localized("Not connected")
        }
        switch network.transport {
        case .wifi: return network.ssid ?? localized("Network name unavailable")
        case .ethernet: return network.interfaceName ?? localized("Wired connection")
        case .other: return network.interfaceName ?? localized("Active connection")
        case .none: return localized("Not connected")
        }
    }

    private var networkState: String {
        let network = statusStore.status.network
        guard network.isAvailable else { return localized("Unavailable") }
        guard network.isConnected else { return localized("Offline") }
        switch network.transport {
        case .wifi: return localized("Wi-Fi")
        case .ethernet: return localized("Ethernet")
        case .other: return localized("Connected")
        case .none: return localized("Offline")
        }
    }

    private var batterySymbol: String {
        let battery = statusStore.status.battery
        if battery.isCharging { return "battery.100percent.bolt" }
        if battery.isFullyCharged { return "battery.100percent" }
        switch battery.percentage ?? 0 {
        case 76...100: return "battery.100percent"
        case 51...75: return "battery.75percent"
        case 26...50: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    private var batteryDetail: String {
        let battery = statusStore.status.battery
        if !battery.isAvailable { return localized("No internal battery") }
        if battery.isFullyCharged { return localized("Fully charged") }
        if battery.isCharging { return localized("Charging") }
        if battery.isLowPowerModeEnabled { return localized("Low Power Mode") }
        if battery.isPluggedIn { return localized("Power adapter connected") }
        return localized("Using battery power")
    }

    private var batteryPercentage: String {
        guard showBatteryPercentage else { return "—" }
        return statusStore.status.battery.percentage.map { localized("%d%%", $0) } ?? "—"
    }

    private var audioOutputSymbol: String {
        guard let output = statusStore.status.audio.defaultOutput else { return "speaker.slash" }
        if output.transport.isBluetooth {
            return output.temporaryGlyph == .airPods ? "airpodspro" : "headphones"
        }
        return "speaker.wave.2"
    }

    private var audioOutputDetail: String {
        statusStore.status.audio.defaultOutput?.name ?? localized("No output device")
    }

    private var audioOutputState: String {
        guard let output = statusStore.status.audio.defaultOutput else { return localized("Unavailable") }
        if output.transport.isBluetooth {
            return output.temporaryGlyph == .airPods ? localized("AirPods") : localized("Bluetooth")
        }
        switch output.transport {
        case .builtIn: return localized("Built-in")
        case .airPlay: return localized("AirPlay")
        case .usb: return localized("USB")
        case .hdmi, .displayPort: return localized("Display")
        case .virtual: return localized("Virtual")
        case .bluetooth, .bluetoothLE: return localized("Bluetooth")
        case .other: return localized("Connected")
        }
    }
}

#if DEBUG
private struct DebugStatusSimulatorView: View {
    let statusStore: SystemStatusStore
    @AppStorage(PreferenceKeys.batteryColorCoding) private var batteryColorCoding = false

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Label("Debug Simulator", systemImage: "hammer")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu("Simulate") {
                    Menu("Battery Level") {
                        ForEach(DebugBatteryLevel.allCases) { level in
                            Button(level.title) { statusStore.applyDebugBatteryLevel(level) }
                        }
                    }
                    Menu("Battery Power") {
                        ForEach(DebugPowerState.allCases) { powerState in
                            Button(powerState.rawValue) { statusStore.applyDebugPowerState(powerState) }
                        }
                    }
                    Menu("Low Power Mode") {
                        ForEach(DebugLowPowerMode.allCases) { lowPowerMode in
                            Button(lowPowerMode.rawValue) { statusStore.applyDebugLowPowerMode(lowPowerMode) }
                        }
                    }
                    Menu("Battery Color Coding") {
                        Button("Off") { batteryColorCoding = false }
                        Button("On") { batteryColorCoding = true }
                    }
                    Menu("Network") {
                        ForEach(DebugNetworkState.allCases) { networkState in
                            Button(networkState.rawValue) { statusStore.applyDebugNetworkState(networkState) }
                        }
                    }
                    Menu("Volume") {
                        ForEach(DebugVolumeState.allCases) { volumeState in
                            Button(volumeState.rawValue) { statusStore.applyDebugVolumeState(volumeState) }
                        }
                    }
                    Menu("Audio Connection") {
                        ForEach(DebugAudioDeviceState.allCases) { deviceState in
                            Button(deviceState.rawValue) { statusStore.applyDebugAudioDeviceState(deviceState) }
                        }
                    }
                    Divider()
                    Button("Restore Live Data") { statusStore.restoreLiveStatus() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
    }
}
#endif
