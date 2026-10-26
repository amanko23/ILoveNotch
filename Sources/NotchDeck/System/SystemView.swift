// SPDX-License-Identifier: MIT
import AppKit
import NotchFeatures
import SwiftUI

/// The System tab: the battery in full, the apps using the most energy, and accessory batteries.
struct SystemView: View {
    let monitor: SystemMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                BatteryStats(battery: monitor.battery)
                if let battery = monitor.battery { details(battery) }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        SectionLabel("Using the most energy now")
                        EnergyList(energy: monitor.energy, limit: 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        SectionLabel("Devices")
                        AccessoryList(accessories: monitor.accessories)
                    }
                    .frame(width: 130, alignment: .leading)
                }
                Detail("Energy covers your own apps; system processes need admin rights to measure.")
            }
            .padding(.vertical, 4)
        }
        .fadingEdges()
    }

    /// The figures that don't fit in three boxes: temperature, the charger, and what the Mac draws.
    private func details(_ battery: BatteryReport) -> some View {
        HStack(spacing: 6) {
            Stat(value: battery.temperature.map { String(format: "%.0f°C", $0) } ?? "—", label: "battery temp")
            Stat(value: battery.adapterWatts.map { "\($0) W" } ?? "—", label: "charger")
            Stat(value: battery.systemWatts.map { String(format: "%.1f W", $0) } ?? "—", label: "Mac draws")
        }
    }
}
