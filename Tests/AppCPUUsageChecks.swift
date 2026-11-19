import Foundation

@main
private struct AppCPUUsageChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func main() {
        expect(AppCPUUsage.percentage(cpuSeconds: 4, elapsed: 2, processorCount: 8) == 25,
               "CPU use must be normalized across all active processors")
        expect(AppCPUUsage.percentage(cpuSeconds: 0, elapsed: 2, processorCount: 8) == 0,
               "No CPU time must produce zero utilization")
        expect(AppCPUUsage.percentage(cpuSeconds: 20, elapsed: 2, processorCount: 8) == 100,
               "A reported value must not exceed 100 percent")
        expect(AppCPUUsage.percentage(cpuSeconds: -1, elapsed: 2, processorCount: 8) == nil,
               "A negative CPU time delta is invalid")
        expect(AppCPUUsage.percentage(cpuSeconds: 1, elapsed: 0, processorCount: 8) == nil,
               "A zero sample interval is invalid")
        expect(AppCPUUsage.percentage(cpuSeconds: 1, elapsed: 1, processorCount: 0) == nil,
               "A zero processor count is invalid")

        let sampler = AppCPUUsage()
        expect(sampler.sample() == nil, "The first sample must establish a baseline")
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        var work: UInt64 = 1
        while ProcessInfo.processInfo.systemUptime < deadline {
            work = work &* 1_664_525 &+ 1_013_904_223
        }
        guard let utilization = sampler.sample() else { fatalError("CPU sample was unavailable") }
        expect(utilization > 0 && utilization <= 100, "A busy process must have a valid CPU reading")
        print("App CPU usage checks passed: \(Int(utilization))%, work=\(work)")
    }
}
