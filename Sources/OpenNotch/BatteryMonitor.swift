import Foundation
import IOKit.ps

/// Battery level and charging state from IOKit, updated by power-source notifications
/// (no polling). `plugInCount` bumps each time the charger is connected.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var hasBattery = false
    @Published private(set) var level: Double = 0       // 0...1
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var plugInCount = 0

    private var source: CFRunLoopSource?

    private init() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() } // delivered on the main run loop
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }

            let pluggedIn = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            if pluggedIn && !isPluggedIn && hasBattery { plugInCount += 1 }

            hasBattery = true
            level = Double(current) / Double(max)
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = pluggedIn
            return
        }
        hasBattery = false
    }
}
