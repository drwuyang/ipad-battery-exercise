import Darwin
import Foundation

// Samples are kept only in memory; 100% means all active CPU cores are busy.
final class AppCPUUsage {
    private struct Snapshot {
        let cpuSeconds: TimeInterval
        let timestamp: TimeInterval
    }

    private var previous: Snapshot?

    func sample() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            previous = nil
            return nil
        }

        let cpuSeconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let current = Snapshot(cpuSeconds: cpuSeconds, timestamp: ProcessInfo.processInfo.systemUptime)
        defer { self.previous = current }
        guard let previous = previous else { return nil }
        return Self.percentage(cpuSeconds: current.cpuSeconds - previous.cpuSeconds,
                               elapsed: current.timestamp - previous.timestamp,
                               processorCount: ProcessInfo.processInfo.activeProcessorCount)
    }

    static func percentage(cpuSeconds: Double, elapsed: Double, processorCount: Int) -> Double? {
        guard cpuSeconds.isFinite, elapsed.isFinite, cpuSeconds >= 0, elapsed > 0, processorCount > 0 else {
            return nil
        }
        return min(100, 100 * cpuSeconds / elapsed / Double(processorCount))
    }
}
