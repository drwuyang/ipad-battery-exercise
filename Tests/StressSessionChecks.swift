import Foundation

private final class FakeWorkload: StressWorkload {
    var starts = 0
    var stops = 0
    var shouldFail = false
    var failures: [(String) -> Void] = []

    func start(onFailure: @escaping (String) -> Void) throws {
        starts += 1
        if shouldFail { throw TestError() }
        failures.append(onFailure)
    }

    func stop() { stops += 1 }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "测试启动失败" }
}

private final class FakeDisplay: StressDisplay {
    var entries = 0
    var restorations = 0
    func enterStressMode() { entries += 1 }
    func restore() { restorations += 1 }
}

@main
@MainActor
private struct StressSessionChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func main() {
        ignoresInvalidAndRepeatedStarts()
        cpuOnlyPausesAndResumes()
        stoppingWhilePausedDoesNotResume()
        failedStartRollsBack()
        staleFailureCannotStopNewRun()
        print("StressSession checks passed")
    }

    static func ignoresInvalidAndRepeatedStarts() {
        let cpu = FakeWorkload(), gpu = FakeWorkload(), display = FakeDisplay()
        let session = StressSession(cpu: cpu, gpu: gpu, display: display)
        session.start(cpu: true, gpu: true)
        session.sceneDidBecomeActive()
        session.start(cpu: false, gpu: false)
        expect(cpu.starts == 0 && gpu.starts == 0, "Invalid start launched work")
        session.start(cpu: true, gpu: true)
        session.start(cpu: true, gpu: true)
        expect(cpu.starts == 1 && gpu.starts == 1, "Repeated start launched duplicate work")
        session.stop()
    }

    static func cpuOnlyPausesAndResumes() {
        let cpu = FakeWorkload(), gpu = FakeWorkload(), display = FakeDisplay()
        let session = StressSession(cpu: cpu, gpu: gpu, display: display)
        session.sceneDidBecomeActive()
        session.start(cpu: true, gpu: false)
        expect(session.state == .running(WorkloadSelection(cpu: true, gpu: false)), "CPU run did not start")
        expect(cpu.starts == 1 && gpu.starts == 0, "Unselected GPU started")
        expect(display.entries == 1, "Display not dimmed")
        session.sceneWillResignActive()
        expect(session.state == .paused(WorkloadSelection(cpu: true, gpu: false)), "Did not pause")
        expect(display.restorations == 1 && cpu.stops == 1, "Pause did not restore and stop")
        session.sceneDidBecomeActive()
        expect(cpu.starts == 2 && gpu.starts == 0, "Resume did not use original selection")
        expect(display.entries == 2, "Display was not dimmed on resume")
        session.stop()
        expect(session.state == .idle && display.restorations == 2, "Stop did not restore idle")
    }

    static func stoppingWhilePausedDoesNotResume() {
        let cpu = FakeWorkload(), gpu = FakeWorkload(), display = FakeDisplay()
        let session = StressSession(cpu: cpu, gpu: gpu, display: display)
        session.sceneDidBecomeActive()
        session.start(cpu: true, gpu: true)
        session.sceneWillResignActive()
        session.stop()
        session.sceneDidBecomeActive()
        expect(session.state == .idle, "Stopped session restarted")
        expect(cpu.starts == 1 && gpu.starts == 1, "Workloads restarted after stop")
    }

    static func failedStartRollsBack() {
        let cpu = FakeWorkload(), gpu = FakeWorkload(), display = FakeDisplay()
        let session = StressSession(cpu: cpu, gpu: gpu, display: display)
        var error = ""
        session.onError = { error = $0 }
        gpu.shouldFail = true
        session.sceneDidBecomeActive()
        session.start(cpu: true, gpu: true)
        expect(session.state == .idle, "Failed start did not return to idle")
        expect(cpu.stops == 1 && gpu.stops == 1, "Failed start did not cancel both workloads")
        expect(display.entries == 0 && error == "测试启动失败", "Failed start did not report error")
    }

    static func staleFailureCannotStopNewRun() {
        let cpu = FakeWorkload(), gpu = FakeWorkload(), display = FakeDisplay()
        let session = StressSession(cpu: cpu, gpu: gpu, display: display)
        var errors = 0
        session.onError = { _ in errors += 1 }
        session.sceneDidBecomeActive()
        session.start(cpu: false, gpu: true)
        let staleFailure = gpu.failures[0]
        session.sceneWillResignActive()
        session.sceneDidBecomeActive()
        staleFailure("old failure")
        expect(session.state == .running(WorkloadSelection(cpu: false, gpu: true)), "Stale error stopped resumed run")
        expect(errors == 0, "Stale error was presented")
        gpu.failures[1]("current failure")
        expect(session.state == .idle && errors == 1, "Current failure was not handled")
    }
}
