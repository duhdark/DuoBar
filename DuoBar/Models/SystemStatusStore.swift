import Combine
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    @Published private(set) var status: SystemStatus = .unavailable

    let priorityController = StatusPriorityController()

    private let batteryService: BatteryService
    private let networkService: NetworkService
    private let audioOutputService: AudioOutputService
    private let bluetoothService: BluetoothService

    #if DEBUG
    private var debugBatteryOverride: BatteryStatus?
    private var debugNetworkOverride: NetworkStatus?
    private var debugAudioOverride: AudioStatus?
    private var debugBluetoothOverride: BluetoothStatus?
    #endif

    init(startServices: Bool = true) {
        batteryService = BatteryService()
        networkService = NetworkService()
        audioOutputService = AudioOutputService()
        bluetoothService = BluetoothService()

        batteryService.onStatusChange = { [weak self] value in
            #if DEBUG
            let percentage = value.percentage.map { "\($0)%" } ?? "unavailable"
            NSLog("%@", "[SystemStatusStore] received battery = \(percentage), charging = \(value.isCharging), pluggedIn = \(value.isPluggedIn)")
            guard self?.debugBatteryOverride == nil else { return }
            #endif
            self?.mutate { $0.battery = value }
        }
        networkService.onStatusChange = { [weak self] value in
            #if DEBUG
            guard self?.debugNetworkOverride == nil else { return }
            #endif
            self?.mutate { $0.network = value }
        }
        audioOutputService.onStatusChange = { [weak self] value in
            #if DEBUG
            guard self?.debugAudioOverride == nil else { return }
            #endif
            self?.mutate { $0.audio = value }
        }
        bluetoothService.onStatusChange = { [weak self] value in
            #if DEBUG
            guard self?.debugBluetoothOverride == nil else { return }
            #endif
            self?.mutate { $0.bluetooth = value }
        }

        if startServices {
            batteryService.start()
            networkService.start()
            audioOutputService.start()
            bluetoothService.start()
        }
    }

    func refresh() {
        batteryService.refresh()
        networkService.refresh()
        audioOutputService.refresh()
        bluetoothService.refresh()
    }

    func requestWiFiSSIDAccess() {
        networkService.requestSSIDAccess()
    }

    @discardableResult
    func setVolume(_ level: Double) -> Bool {
        #if DEBUG
        if var audio = debugAudioOverride {
            guard audio.volume.isSettable else { return false }
            audio.volume.level = min(max(level, 0), 1)
            audio.volume.isMuted = level == 0
            debugAudioOverride = audio
            mutate { $0.audio = audio }
            return true
        }
        #endif
        return audioOutputService.setVolume(level)
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        #if DEBUG
        if var audio = debugAudioOverride {
            guard audio.volume.isMuteSettable else { return false }
            audio.volume.isMuted = muted
            debugAudioOverride = audio
            mutate { $0.audio = audio }
            return true
        }
        #endif
        return audioOutputService.setMuted(muted)
    }

    @discardableResult
    func setDefaultOutput(uid: String) -> Bool {
        #if DEBUG
        if var audio = debugAudioOverride {
            guard let device = audio.selectableOutputs.first(where: { $0.uid == uid }) else {
                return false
            }
            audio.defaultOutput = device
            audio.connectedBluetoothOutputs = audio.selectableOutputs.filter(\.transport.isBluetooth)
            debugAudioOverride = audio
            mutate { $0.audio = audio }
            return true
        }
        #endif
        return audioOutputService.setDefaultOutput(uid: uid)
    }

    private func mutate(_ update: (inout SystemStatus) -> Void) {
        let previous = status
        var next = status
        update(&next)
        guard next != previous else { return }

        status = next
        StatusEventDetector.events(from: previous, to: next).forEach(priorityController.present)
    }

    #if DEBUG
    func applyDebugBatteryLevel(_ level: DebugBatteryLevel) {
        var battery = debugBatteryOverride ?? status.battery
        battery.percentage = level.rawValue
        battery.isAvailable = true
        battery.isFullyCharged = level.rawValue == 100 && battery.isPluggedIn && !battery.isCharging
        debugBatteryOverride = battery
        mutate { $0.battery = battery }
    }

    func applyDebugPowerState(_ powerState: DebugPowerState) {
        var battery = debugBatteryOverride ?? status.battery
        if !battery.isAvailable {
            battery = BatteryStatus(
                percentage: 75,
                isCharging: false,
                isPluggedIn: false,
                isFullyCharged: false,
                isAvailable: true
            )
        }
        battery.isCharging = powerState.isCharging
        battery.isPluggedIn = powerState.isPluggedIn
        battery.isFullyCharged = powerState.isFullyCharged
        if powerState.isFullyCharged {
            battery.percentage = 100
        }
        debugBatteryOverride = battery
        mutate { $0.battery = battery }
    }

    func applyDebugLowPowerMode(_ lowPowerMode: DebugLowPowerMode) {
        var battery = debugBatteryOverride ?? status.battery
        if !battery.isAvailable {
            battery = BatteryStatus(
                percentage: 50,
                isCharging: false,
                isPluggedIn: false,
                isFullyCharged: false,
                isAvailable: true
            )
        }
        battery.isLowPowerModeEnabled = lowPowerMode.isEnabled
        debugBatteryOverride = battery
        mutate { $0.battery = battery }
    }

    func applyDebugNetworkState(_ networkState: DebugNetworkState) {
        debugNetworkOverride = networkState.status
        mutate { $0.network = networkState.status }
    }

    func applyDebugVolumeState(_ volumeState: DebugVolumeState) {
        var audio = debugAudioOverride ?? status.audio
        audio.isAvailable = true
        audio.volume = volumeState.status
        if audio.defaultOutput == nil {
            audio.defaultOutput = DebugAudioDeviceState.builtIn.status.defaultOutput
        }
        debugAudioOverride = audio
        mutate { $0.audio = audio }
    }

    func applyDebugAudioDeviceState(_ deviceState: DebugAudioDeviceState) {
        let audio = deviceState.status
        if deviceState != .builtIn {
            let baseline = DebugAudioDeviceState.builtIn.status
            debugAudioOverride = baseline
            mutate { $0.audio = baseline }
        }
        debugAudioOverride = audio
        mutate { $0.audio = audio }
    }

    func applyDebugBluetoothState(_ bluetoothState: DebugBluetoothState) {
        debugBluetoothOverride = bluetoothState.status
        mutate { $0.bluetooth = bluetoothState.status }
    }

    func restoreLiveStatus() {
        debugBatteryOverride = nil
        debugNetworkOverride = nil
        debugAudioOverride = nil
        debugBluetoothOverride = nil
        priorityController.returnToNormal()
        refresh()
    }

    func applyMarketingCaptureState(_ identifier: String) {
        var battery = BatteryStatus(
            percentage: 75,
            isCharging: false,
            isPluggedIn: false,
            isFullyCharged: false,
            isAvailable: true
        )
        var network = NetworkStatus(
            isAvailable: true,
            isConnected: true,
            transport: .wifi,
            interfaceName: "en0",
            isWiFiPoweredOn: true,
            ssid: "Wi-Fi Network",
            rssi: -42
        )
        let outputDevice = AudioDeviceStatus(
            uid: "marketing-built-in-output",
            name: "MacBook Speakers",
            transport: .builtIn,
            isAlive: true
        )
        var audio = AudioStatus(
            isAvailable: true,
            defaultOutput: outputDevice,
            volume: OutputVolumeStatus(level: 0.75, isMuted: false, isSettable: true, isMuteSettable: true),
            connectedBluetoothOutputs: [],
            availableOutputs: [outputDevice]
        )
        var bluetooth = BluetoothStatus(isAvailable: true, isPoweredOn: true)

        switch identifier {
        case "battery100":
            battery.percentage = 100
        case "battery50":
            battery.percentage = 50
        case "lowBattery":
            battery.percentage = 8
        case "charging":
            battery.percentage = 60
            battery.isCharging = true
            battery.isPluggedIn = true
        case "wifiDisconnected":
            network.isConnected = false
            network.ssid = nil
            network.rssi = nil
        case "bluetoothOff":
            bluetooth.isPoweredOn = false
        case "volumeMuted":
            audio.volume = OutputVolumeStatus(level: 0, isMuted: true, isSettable: true)
        case "hero", "bluetoothOn":
            break
        default:
            return
        }

        debugBatteryOverride = battery
        debugNetworkOverride = network
        debugAudioOverride = audio
        debugBluetoothOverride = bluetooth
        priorityController.returnToNormal()
        mutate {
            $0.battery = battery
            $0.network = network
            $0.audio = audio
            $0.bluetooth = bluetooth
        }
    }
    #endif
}
