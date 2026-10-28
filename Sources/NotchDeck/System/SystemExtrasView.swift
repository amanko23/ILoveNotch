// SPDX-License-Identifier: MIT
import SwiftUI

/// CPU, GPU, and temperature, each its latest reading over a two-minute graph.
struct PerformanceGraphs: View {
    let performance: PerformanceSampler

    var body: some View {
        HStack(spacing: 6) {
            GraphCard(label: "CPU", values: performance.cpu, unit: "%", ceiling: 100)
            GraphCard(label: "GPU", values: performance.gpu, unit: "%", ceiling: 100)
            GraphCard(label: "CPU temp", values: performance.temperature, unit: "°C", ceiling: 105)
        }
    }
}

private struct GraphCard: View {
    let label: String
    let values: [Double]
    let unit: String
    let ceiling: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(values.last.map { String(format: "%.0f", $0) + unit } ?? "—")
                    .font(Viorim.metric(15)).monospacedDigit().foregroundStyle(Viorim.ink)
                Text(label).font(.system(size: 9.5)).foregroundStyle(Viorim.ink2).lineLimit(1)
            }
            Sparkline(values: values, ceiling: ceiling).frame(height: 22)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Viorim.surfaceSunken.opacity(0.55), in: RoundedRectangle(cornerRadius: Viorim.radiusWell))
        .accessibilityElement(children: .combine)
    }
}

/// A line over the last readings, scaled to `ceiling`, with a soft fill under it.
struct Sparkline: View {
    let values: [Double]
    let ceiling: Double

    var body: some View {
        GeometryReader { geometry in
            let points = points(in: geometry.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Viorim.accent.opacity(0.28), Viorim.accent.opacity(0)], startPoint: .top,
                        endPoint: .bottom))
                    Path { path in path.addLines(points) }
                        .stroke(Viorim.accent, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .animation(Viorim.smooth, value: values)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let step = size.width / CGFloat(max(1, PerformanceSampler.capacity - 1))
        let start = size.width - step * CGFloat(max(0, values.count - 1))
        return values.enumerated().map { index, value in
            let y = size.height * (1 - CGFloat(min(1, max(0, value / ceiling))))
            return CGPoint(x: start + step * CGFloat(index), y: y)
        }
    }
}

/// Keep the display awake: off, for a while, or until turned off.
struct KeepAwakeRow: View {
    let keepAwake: KeepAwake

    var body: some View {
        HStack(spacing: 6) {
            SectionLabel("Keep awake")
            Spacer(minLength: 4)
            if let until = keepAwake.until {
                Text("until \(IST.time(until))").font(Viorim.footnote).foregroundStyle(Viorim.ink2)
            }
            ForEach(KeepAwake.Length.allCases) { length in
                PillButton(length.title, prominent: keepAwake.length == length) { keepAwake.keep(length) }
            }
        }
    }
}

/// A slider per display: hardware brightness where macOS allows it, a software dim elsewhere.
struct BrightnessList: View {
    let brightness: Brightness

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel("Brightness")
            ForEach(brightness.displays) { display in
                HStack(spacing: 8) {
                    Text(display.name).font(Viorim.footnote).foregroundStyle(Viorim.ink).lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    Slider(
                        value: Binding(get: { display.level }, set: { brightness.set($0, for: display.id) }),
                        in: 0...1
                    )
                    .controlSize(.mini)
                    .tint(Viorim.accent)
                    Text(display.hardware ? "\(Int(display.level * 100))%" : "Dim")
                        .font(Viorim.footnote).monospacedDigit().foregroundStyle(Viorim.ink2)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }
}

/// Battery alerts: on or off, at what charge, and whether to say when it's charged.
struct BatteryAlertsRow: View {
    @Bindable var alerts: BatteryAlerts

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Battery alerts", isOn: $alerts.isEnabled).toggleStyle(.switch).controlSize(.mini)
                .font(Viorim.footnote)
            Spacer(minLength: 4)
            Picker("Low at", selection: $alerts.lowThreshold) {
                ForEach([10, 15, 20, 25, 30], id: \.self) { Text("Low at \($0)%").tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Charged", selection: $alerts.fullThreshold) {
                Text("No charged alert").tag(Int?.none)
                Text("Charged at 80%").tag(Int?.some(80))
                Text("Charged at 100%").tag(Int?.some(100))
            }
            .labelsHidden()
            .fixedSize()
        }
        .controlSize(.mini)
    }
}
