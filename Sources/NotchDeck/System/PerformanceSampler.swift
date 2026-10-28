// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import IOKit
import Observation

/// The processor's and graphics' load and the CPU's temperature, a reading every two seconds and the
/// last two minutes kept for graphs. It samples only between `start()` and `stop()`.
@MainActor
@Observable
public final class PerformanceSampler {
    /// Readings oldest first: CPU and GPU in percent, temperature in °C.
    public private(set) var cpu: [Double] = []
    public private(set) var gpu: [Double] = []
    public private(set) var temperature: [Double] = []
    /// How many readings each graph keeps.
    public static let capacity = 60
    @ObservationIgnored private var sampler: Task<Void, Never>?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var smc: SMC?

    public init() {}

    public func start() {
        guard sampler == nil else { return }
        smc = SMC()
        lastTicks = CPUTicks.read()
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2), tolerance: .milliseconds(300)) } catch { return }
                self?.sample()
            }
        }
    }

    public func stop() {
        sampler?.cancel()
        sampler = nil
        smc = nil
    }

    private func sample() {
        if let ticks = CPUTicks.read() {
            if let last = lastTicks, let load = ticks.load(since: last) { Self.append(load, to: &cpu) }
            lastTicks = ticks
        }
        if let load = Self.gpuLoad() { Self.append(load, to: &gpu) }
        if let celsius = smc?.cpuTemperature() { Self.append(celsius, to: &temperature) }
    }

    nonisolated static func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > capacity { history.removeFirst(history.count - capacity) }
    }

    /// The busiest GPU's utilization from the accelerator's own statistics, nil where it has none.
    nonisolated static func gpuLoad() -> Double? {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
                == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let stats =
                IORegistryEntryCreateCFProperty(
                    service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            let value = (stats?["Device Utilization %"] ?? stats?["GPU Activity(%)"]) as? NSNumber
            if let value { best = max(best ?? 0, min(100, value.doubleValue)) }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best
    }
}

/// The whole processor's ticks so far, busy and in total.
struct CPUTicks: Equatable, Sendable {
    var busy: UInt64
    var total: UInt64

    private static let host = mach_host_self()

    static func read() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let (user, system, idle, nice) = info.cpu_ticks
        let busy = UInt64(user) + UInt64(system) + UInt64(nice)
        return CPUTicks(busy: busy, total: busy + UInt64(idle))
    }

    /// Percent busy between `earlier` and now, nil if no time passed.
    func load(since earlier: CPUTicks) -> Double? {
        guard total > earlier.total, busy >= earlier.busy else { return nil }
        return min(100, Double(busy - earlier.busy) / Double(total - earlier.total) * 100)
    }
}

/// A read-only connection to the System Management Controller, for the CPU's temperature. Intel
/// Macs name it TC0P and friends; Apple silicon uses other keys, and where none answers the
/// temperature is simply missing.
final class SMC {
    private var connection: io_connect_t = 0

    private static let keys = ["TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D"]
    /// The first key that answered, so later reads skip the rest.
    private var key: String?

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, task_self_trap(), 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(connection) }

    func cpuTemperature() -> Double? {
        if let key, let value = read(key) { return value }
        for candidate in Self.keys {
            if let value = read(candidate) {
                key = candidate
                return value
            }
        }
        return nil
    }

    // SMCKeyData_t is 80 bytes: key at 0, keyInfo.dataSize at 28, keyInfo.dataType at 32, result at
    // 40, data8 (the command) at 42, bytes at 48.
    private static let size = 80

    private func read(_ key: String) -> Double? {
        let code = Self.fourCharCode(key)
        var input = [UInt8](repeating: 0, count: Self.size)
        input.withUnsafeMutableBytes {
            $0.storeBytes(of: code, toByteOffset: 0, as: UInt32.self)
            $0[42] = 9  // kSMCGetKeyInfo
        }
        guard let info = call(input) else { return nil }
        let dataSize = info.withUnsafeBytes { $0.load(fromByteOffset: 28, as: UInt32.self) }
        let dataType = info.withUnsafeBytes { $0.load(fromByteOffset: 32, as: UInt32.self) }
        guard dataSize > 0, dataSize <= 32 else { return nil }
        input.withUnsafeMutableBytes {
            $0.storeBytes(of: dataSize, toByteOffset: 28, as: UInt32.self)
            $0[42] = 5  // kSMCReadKey
        }
        guard let output = call(input) else { return nil }
        let bytes = Array(output[48..<(48 + Int(dataSize))])
        guard let value = Self.decode(bytes, type: dataType), value > 0, value < 130 else { return nil }
        return value
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Self.size)
        var outputSize = Self.size
        let result = input.withUnsafeBytes { inBytes in
            output.withUnsafeMutableBytes { outBytes in
                IOConnectCallStructMethod(
                    connection, 2, inBytes.baseAddress, Self.size, outBytes.baseAddress, &outputSize)
            }
        }
        guard result == KERN_SUCCESS, output[40] == 0 else { return nil }
        return output
    }

    /// A temperature in the SMC's encodings: sp78 (signed 8.8 fixed point, big-endian) or flt (a
    /// little-endian Float).
    static func decode(_ bytes: [UInt8], type: UInt32) -> Double? {
        switch type {
        case fourCharCode("sp78") where bytes.count >= 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case fourCharCode("flt ") where bytes.count >= 4:
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        default:
            return nil
        }
    }

    static func fourCharCode(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
}
