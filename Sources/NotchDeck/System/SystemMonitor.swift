// SPDX-License-Identifier: MIT
import Foundation
import Observation

/// The battery, the apps using the most energy, and accessory batteries, shared by Home's System
/// tile and the System tab. It runs only while one of them is on screen: then it samples energy
/// every few seconds and reads the battery every ten; otherwise it does nothing at all.
@MainActor
@Observable
public final class SystemMonitor {
    public private(set) var battery: BatteryReport?
    public private(set) var accessories: [AccessoryBattery] = []
    public let energy = EnergySampler()
    /// Who's showing it right now: Home, the System tab, or both.
    @ObservationIgnored private var viewers: Set<String> = []
    @ObservationIgnored private var refresher: Task<Void, Never>?

    public init() {
        battery = BatteryReport.read()  // one read so the first frame has a charge to show
    }

    public var isRunning: Bool { refresher != nil }

    public func start(for viewer: String) {
        viewers.insert(viewer)
        guard refresher == nil else { return }
        energy.start()
        refresher = Task { [weak self] in
            while !Task.isCancelled {
                let (battery, accessories) = await Task.detached(priority: .utility) {
                    (BatteryReport.read(), AccessoryBattery.readAll())
                }.value
                guard let self, !Task.isCancelled else { return }
                if self.battery != battery { self.battery = battery }
                if self.accessories != accessories { self.accessories = accessories }
                do { try await Task.sleep(for: .seconds(10), tolerance: .seconds(1)) } catch { return }
            }
        }
    }

    public func stop(for viewer: String) {
        viewers.remove(viewer)
        guard viewers.isEmpty else { return }
        refresher?.cancel()
        refresher = nil
        energy.stop()
    }
}
