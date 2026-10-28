// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchDeck

struct SystemExtrasTests {
    @Test func cpuLoadIsTheBusyShareOfTicksSinceTheLastReading() {
        let earlier = CPUTicks(busy: 100, total: 400)
        #expect(CPUTicks(busy: 150, total: 600).load(since: earlier) == 25)
        #expect(CPUTicks(busy: 100, total: 400).load(since: earlier) == nil)
    }

    @Test func historiesKeepTheLastSixtyReadings() {
        var history: [Double] = []
        for value in 0..<70 { PerformanceSampler.append(Double(value), to: &history) }
        #expect(history.count == PerformanceSampler.capacity && history.first == 10 && history.last == 69)
    }

    @Test func smcTemperaturesDecodeBothEncodings() {
        #expect(SMC.decode([0x2D, 0x80], type: SMC.fourCharCode("sp78")) == 45.5)
        let bits = Float(52.25).bitPattern
        let little = [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)]
        #expect(SMC.decode(little, type: SMC.fourCharCode("flt ")) == 52.25)
        #expect(SMC.fourCharCode("TC0P") == 0x5443_3050)
    }

    @Test func batteryAlertsSoundOnceWhenAThresholdIsCrossed() {
        typealias Reading = BatteryAlerts.Reading
        let low = BatteryAlerts.alert(
            from: Reading(percent: 21, onAC: false), to: Reading(percent: 20, onAC: false), low: 20, full: nil)
        #expect(low?.title == "Battery low: 20%")
        #expect(
            BatteryAlerts.alert(
                from: Reading(percent: 20, onAC: false), to: Reading(percent: 19, onAC: false), low: 20, full: nil)
                == nil)
        let charged = BatteryAlerts.alert(
            from: Reading(percent: 79, onAC: true), to: Reading(percent: 80, onAC: true), low: 20, full: 80)
        #expect(charged?.title == "Charged to 80%")
        #expect(
            BatteryAlerts.alert(
                from: Reading(percent: 85, onAC: true), to: Reading(percent: 86, onAC: true), low: 20, full: 80)
                == nil)
    }
}
