// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Observation
import UserNotifications

// MARK: Battery alerts

/// Tells you when the battery runs low, and optionally when it's charged. It listens for the power
/// source's own change notifications, so it costs nothing between them, on screen or not.
@MainActor
@Observable
public final class BatteryAlerts {
    /// A moment of the battery, as the power source APIs report it.
    struct Reading: Equatable, Sendable {
        var percent: Int
        var onAC: Bool
    }

    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }
    /// Alert once the charge falls to this percentage on battery.
    public var lowThreshold: Int {
        didSet { defaults.set(lowThreshold, forKey: Key.low) }
    }
    /// Alert once the charge reaches this on the charger, or never when nil (80 or 100).
    public var fullThreshold: Int? {
        didSet { defaults.set(fullThreshold ?? 0, forKey: Key.full) }
    }
    /// Called with a symbol and a title for the notch.
    @ObservationIgnored public var onAlert: ((String, String) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var last: Reading?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        lowThreshold = defaults.object(forKey: Key.low) as? Int ?? 20
        let full = defaults.integer(forKey: Key.full)
        fullThreshold = full > 0 ? full : nil
    }

    public func start() {
        guard source == nil else { return }
        last = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(batteryPowerChanged, context)?.takeRetainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
    }

    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
    }

    fileprivate func powerChanged() {
        guard let now = Self.read() else { return }
        defer { last = now }
        guard isEnabled, let alert = Self.alert(from: last, to: now, low: lowThreshold, full: fullThreshold)
        else { return }
        onAlert?(alert.symbol, alert.title)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "battery", content: content, trigger: nil), withCompletionHandler: nil)
    }

    /// The alert a change from `previous` to `now` calls for: only when a threshold is crossed, so
    /// each one sounds once.
    nonisolated static func alert(
        from previous: Reading?, to now: Reading, low: Int, full: Int?
    ) -> (symbol: String, title: String)? {
        if !now.onAC, now.percent <= low, previous.map({ $0.onAC || $0.percent > low }) ?? true {
            return ("battery.25percent", "Battery low: \(now.percent)%")
        }
        if let full, now.onAC, now.percent >= full, let previous, previous.percent < full || !previous.onAC {
            return ("battery.100percent.bolt", full >= 100 ? "Fully charged" : "Charged to \(now.percent)%")
        }
        return nil
    }

    nonisolated static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            guard let description, description["Type"] as? String == "InternalBattery",
                let current = description["Current Capacity"] as? Int,
                let maximum = description["Max Capacity"] as? Int, maximum > 0
            else { continue }
            let onAC = description["Power Source State"] as? String == "AC Power"
            return Reading(percent: current * 100 / maximum, onAC: onAC)
        }
        return nil
    }

    private enum Key {
        static let enabled = "system.batteryAlerts"
        static let low = "system.batteryLow"
        static let full = "system.batteryFull"
    }
}

/// The power source's change callback: a plain C function, so it carries no actor. Its run loop
/// source is on the main run loop, so it's called on the main thread.
private func batteryPowerChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let alerts = Unmanaged<BatteryAlerts>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { alerts.powerChanged() }
}

// MARK: Keep awake

/// Keeps the display awake for a while, or until turned off, with a power assertion like
/// `caffeinate -d`. The deadline is a wall-clock one: a single sleep until then.
@MainActor
@Observable
public final class KeepAwake {
    public enum Length: String, CaseIterable, Identifiable, Sendable {
        case off, halfHour, hour, twoHours, indefinitely

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .off: "Off"
            case .halfHour: "30m"
            case .hour: "1h"
            case .twoHours: "2h"
            case .indefinitely: "∞"
            }
        }
        var seconds: TimeInterval? {
            switch self {
            case .off, .indefinitely: nil
            case .halfHour: 1800
            case .hour: 3600
            case .twoHours: 7200
            }
        }
    }

    public private(set) var length: Length = .off
    /// When it lets the Mac sleep again; nil while off or indefinite.
    public private(set) var until: Date?
    public var isOn: Bool { length != .off }
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var deadline: Task<Void, Never>?

    public init() {}

    public func keep(_ length: Length) {
        release()
        guard length != .off else { return }
        var id: IOPMAssertionID = 0
        let created = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "NotchDeck: Keep awake" as CFString, &id)
        guard created == 0 else { return }  // kIOReturnSuccess
        assertion = id
        self.length = length
        guard let seconds = length.seconds else { return }
        until = Date.now.addingTimeInterval(seconds)
        deadline = Task { [weak self] in
            // The continuous clock keeps counting while the Mac sleeps, so the deadline holds.
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.keep(.off)
        }
    }

    private func release() {
        deadline?.cancel()
        deadline = nil
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        length = .off
        until = nil
    }
}

// MARK: Brightness

/// Each display's brightness: the built-in one (and Apple displays) in hardware through the private
/// DisplayServices framework, others dimmed in software by scaling their gamma, which macOS undoes
/// when NotchDeck quits.
@MainActor
@Observable
public final class Brightness {
    public struct Display: Identifiable, Hashable, Sendable {
        public var id: CGDirectDisplayID
        public var name: String
        /// Whether it's set in hardware; otherwise it's a software dim.
        public var hardware: Bool
        /// 0...1.
        public var level: Double
    }

    public private(set) var displays: [Display] = []
    /// Software dims, by display, kept while NotchDeck runs.
    @ObservationIgnored private var dims: [CGDirectDisplayID: Double] = [:]

    public init() {}

    /// Reads the displays and their levels again, as the System tab appears.
    public func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            if let level = Self.hardwareLevel(id) {
                return Display(id: id, name: screen.localizedName, hardware: true, level: level)
            }
            return Display(id: id, name: screen.localizedName, hardware: false, level: dims[id] ?? 1)
        }
    }

    public func set(_ level: Double, for id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let level = min(1, max(0, level))
        displays[index].level = level
        if displays[index].hardware {
            _ = Self.setBrightness?(id, Float(level))
        } else {
            // Never all the way to black: a dimmed display must stay readable enough to undo it.
            let scale = Float(0.25 + 0.75 * level)
            dims[id] = level
            CGSetDisplayTransferByFormula(id, 0, scale, 1, 0, scale, 1, 0, scale, 1)
        }
    }

    private static func hardwareLevel(_ id: CGDirectDisplayID) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(id, &value) == 0 else { return nil }
        return Double(value)
    }

    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getBrightness: Getter? = framework.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: Getter.self) }
    private static let setBrightness: Setter? = framework.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: Setter.self) }
}
