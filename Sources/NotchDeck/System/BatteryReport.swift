// SPDX-License-Identifier: MIT
import Foundation
import IOKit

/// The internal battery as the I/O Registry's `AppleSmartBattery` describes it: more than the power
/// source APIs give (cycle count, health, temperature, watts), read-only and without any entitlement.
public struct BatteryReport: Equatable, Sendable {
    /// 0...100.
    public var percent: Int
    public var isCharging: Bool
    /// Plugged into a charger, charging or not.
    public var onAC: Bool
    public var fullyCharged: Bool
    public var cycleCount: Int?
    /// What the battery holds now, as a percentage of what it held new, the way System Settings
    /// shows Maximum Capacity: at most 100.
    public var health: Int?
    /// Degrees Celsius.
    public var temperature: Double?
    /// Power into the battery (positive, charging) or out of it (negative), in watts.
    public var batteryWatts: Double?
    /// The charger's rating, in watts.
    public var adapterWatts: Int?
    /// What the whole Mac draws right now, in watts, where the battery reports it.
    public var systemWatts: Double?
    /// Until full while charging, or until empty on battery; nil while macOS is still estimating.
    public var minutesRemaining: Int?

    public init(
        percent: Int, isCharging: Bool, onAC: Bool, fullyCharged: Bool, cycleCount: Int? = nil, health: Int? = nil,
        temperature: Double? = nil, batteryWatts: Double? = nil, adapterWatts: Int? = nil, systemWatts: Double? = nil,
        minutesRemaining: Int? = nil
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.onAC = onAC
        self.fullyCharged = fullyCharged
        self.cycleCount = cycleCount
        self.health = health
        self.temperature = temperature
        self.batteryWatts = batteryWatts
        self.adapterWatts = adapterWatts
        self.systemWatts = systemWatts
        self.minutesRemaining = minutesRemaining
    }

    /// Reads the battery now, or nil on a Mac without one.
    public static func read() -> BatteryReport? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return BatteryReport(registry: dictionary)
    }

    /// Builds a report from `AppleSmartBattery`'s properties. Apple silicon reports the charge as a
    /// percentage (`MaxCapacity` 100) and capacities in mAh under `AppleRaw…` and `Nominal…`; Intel
    /// Macs report mAh throughout. Both work here.
    init?(registry: [String: Any]) {
        func int(_ key: String) -> Int? { (registry[key] as? NSNumber)?.intValue }
        guard let current = int("CurrentCapacity"), let maximum = int("MaxCapacity"), maximum > 0 else { return nil }
        percent = min(max(current * 100 / maximum, 0), 100)
        isCharging = registry["IsCharging"] as? Bool ?? false
        onAC = registry["ExternalConnected"] as? Bool ?? false
        fullyCharged = registry["FullyCharged"] as? Bool ?? false
        cycleCount = int("CycleCount")
        if let design = int("DesignCapacity"), design > 0,
            let holds = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity")
        {
            health = min(max(holds * 100 / design, 0), 100)
        }
        temperature = int("Temperature").map { Double($0) / 100 }
        // Amperage is signed, but the registry can hand it over as its unsigned bit pattern.
        if let amperage = registry["InstantAmperage"] as? NSNumber ?? registry["Amperage"] as? NSNumber,
            let millivolts = int("Voltage") ?? int("AppleRawBatteryVoltage")
        {
            let milliamps = Int64(bitPattern: amperage.uint64Value)
            batteryWatts = Double(milliamps) * Double(millivolts) / 1_000_000
        }
        adapterWatts = ((registry["AdapterDetails"] as? [String: Any])?["Watts"] as? NSNumber)?.intValue
        if let load = ((registry["PowerTelemetryData"] as? [String: Any])?["SystemLoad"] as? NSNumber)?.intValue,
            load > 0
        {
            systemWatts = Double(load) / 1000
        }
        // 65535 means macOS is still working it out.
        let minutes = isCharging ? int("AvgTimeToFull") : (onAC ? nil : int("AvgTimeToEmpty"))
        minutesRemaining = minutes.flatMap { (1..<6000).contains($0) ? $0 : nil }
    }

    /// "2:15": hours and minutes.
    public var remainingText: String? {
        minutesRemaining.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
    }

    /// The SF Symbol for this charge, with a bolt while plugged in.
    public var symbol: String {
        if onAC { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// "Charging", "Charged", "On power", or "On battery".
    public var powerText: String {
        if isCharging { return "Charging" }
        if onAC { return fullyCharged ? "Charged" : "On power" }
        return "On battery"
    }
}

/// A Bluetooth keyboard, mouse, or trackpad's battery. Apple's accessories publish `BatteryPercent`
/// in the I/O Registry; AirPods and most others don't share theirs with apps.
public struct AccessoryBattery: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var percent: Int

    public init(name: String, percent: Int) {
        self.name = name
        self.percent = percent
    }

    public var symbol: String {
        let lowered = name.lowercased()
        if lowered.contains("mouse") { return "magicmouse.fill" }
        if lowered.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if lowered.contains("keyboard") { return "keyboard.fill" }
        return "dot.radiowaves.left.and.right"
    }

    /// Every connected accessory that reports a battery, by name.
    public static func readAll() -> [AccessoryBattery] {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator)
                == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [String: Int] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let name = property(service, "Product") as? String,
                let percent = (property(service, "BatteryPercent") as? NSNumber)?.intValue
            else { continue }
            found[name] = min(max(percent, 0), 100)
        }
        return found.map { AccessoryBattery(name: $0.key, percent: $0.value) }.sorted { $0.name < $1.name }
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
