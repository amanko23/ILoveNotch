// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import Observation

/// An app's share of the Mac's energy right now: every process inside its bundle (Chrome's helpers
/// count as Chrome), averaged over the last sample.
public struct AppEnergy: Identifiable, Hashable, Sendable {
    /// The app bundle's path, or the executable's for a process outside any app.
    public var id: String
    public var name: String
    /// Watts.
    public var watts: Double
    /// Whether `id` is an app bundle, which has an icon and can be brought forward.
    public var isApp: Bool

    public init(id: String, name: String, watts: Double, isApp: Bool) {
        self.id = id
        self.name = name
        self.watts = watts
        self.isApp = isApp
    }

    /// "2.1 W", or "0.4 W".
    public var wattsText: String { String(format: watts >= 10 ? "%.0f W" : "%.1f W", watts) }
}

/// Every process's energy counter at one moment: `proc_pid_rusage`'s `ri_energy_nj`, the
/// nanojoules a process has used since it started. macOS answers for the user's own processes
/// without any privilege; system processes need root and are left out.
struct EnergySnapshot: Sendable {
    struct Process: Sendable {
        var nanojoules: UInt64
        var path: String
    }

    var taken: ContinuousClock.Instant
    var processes: [pid_t: Process]

    static func take(reusing paths: [pid_t: String] = [:]) -> EnergySnapshot {
        let taken = ContinuousClock.now
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return EnergySnapshot(taken: taken, processes: [:]) }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var processes: [pid_t: Process] = [:]
        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            var info = rusage_info_v6()
            let read = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, Int32(RUSAGE_INFO_V6), $0)
                }
            }
            guard read == 0, let path = paths[pid] ?? Self.path(of: pid) else { continue }
            processes[pid] = Process(nanojoules: info.ri_energy_nj, path: path)
        }
        return EnergySnapshot(taken: taken, processes: processes)
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The apps that used the most power between `earlier` and `later`, most first, grouped by app
    /// bundle. Processes that started or ended in between are left out of that sample.
    static func ranking(from earlier: EnergySnapshot, to later: EnergySnapshot, limit: Int) -> [AppEnergy] {
        let elapsed = later.taken - earlier.taken
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        guard seconds > 0.1 else { return [] }
        var watts: [String: Double] = [:]
        for (pid, now) in later.processes {
            guard let before = earlier.processes[pid], before.path == now.path,
                now.nanojoules >= before.nanojoules
            else { continue }
            watts[owner(of: now.path), default: 0] += Double(now.nanojoules - before.nanojoules) / 1e9 / seconds
        }
        return
            watts
            .filter { $0.value >= 0.05 }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { path, watts in
                let isApp = path.hasSuffix(".app")
                let name =
                    isApp
                    ? FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                    : URL(filePath: path).lastPathComponent
                return AppEnergy(id: path, name: name, watts: watts, isApp: isApp)
            }
    }

    /// The outermost app bundle around `path`, so helpers nested inside an app count as the app;
    /// the executable itself for anything outside one.
    static func owner(of path: String) -> String {
        guard let range = path.range(of: ".app/") else { return path }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

/// Samples which apps use the most energy, every few seconds and only while something on screen
/// shows it. Each sample runs off the main thread.
@MainActor
@Observable
public final class EnergySampler {
    /// The latest ranking, most first.
    public private(set) var top: [AppEnergy] = []
    /// Whether a first ranking is still on its way.
    public private(set) var isMeasuring = false
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { task != nil }

    public func start(every interval: Duration = .seconds(3), limit: Int = 8) {
        guard task == nil else { return }
        isMeasuring = top.isEmpty
        task = Task { [weak self] in
            var previous = await Task.detached(priority: .utility) { EnergySnapshot.take() }.value
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval, tolerance: .milliseconds(500)) } catch { return }
                let paths = previous.processes.mapValues(\.path)
                let earlier = previous
                let (latest, ranking) = await Task.detached(priority: .utility) {
                    let latest = EnergySnapshot.take(reusing: paths)
                    return (latest, EnergySnapshot.ranking(from: earlier, to: latest, limit: limit))
                }.value
                previous = latest
                guard let self, !Task.isCancelled else { return }
                self.top = ranking
                self.isMeasuring = false
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isMeasuring = false
    }
}
