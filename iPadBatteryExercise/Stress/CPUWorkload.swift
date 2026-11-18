import Accelerate
import Darwin
import Foundation

enum WorkloadError: LocalizedError {
    case cpuMemory
    case gpuUnavailable
    case gpuSetup(String)

    var errorDescription: String? {
        switch self {
        case .cpuMemory: return "无法为 CPU 测试分配内存。"
        case .gpuUnavailable: return "无法使用此设备的 Metal GPU。"
        case let .gpuSetup(detail): return "GPU 测试启动失败：\(detail)"
        }
    }
}

// The lock also makes GPU cancellation atomic with respect to command submission.
final class WorkCancellation {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func submitIfActive(_ submit: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        submit()
        return true
    }
}

private final class CPUWorker {
    private static let count = 65_536
    private let storage: UnsafeMutablePointer<Float>

    init() throws {
        let byteCount = Self.count * 3 * MemoryLayout<Float>.stride
        guard let raw = malloc(byteCount) else { throw WorkloadError.cpuMemory }
        storage = raw.bindMemory(to: Float.self, capacity: Self.count * 3)
        storage.initialize(repeating: 0.25, count: Self.count * 3)
    }

    deinit {
        storage.deinitialize(count: Self.count * 3)
        free(storage)
    }

    func run(until cancellation: WorkCancellation) {
        let a = storage
        let b = storage.advanced(by: Self.count)
        let output = storage.advanced(by: Self.count * 2)
        let count = vDSP_Length(Self.count)
        var scale: Float = 0.9999
        while !cancellation.isCancelled {
            vDSP_vadd(a, 1, b, 1, output, 1, count)
            vDSP_vsmul(output, 1, &scale, a, 1, count)
        }
    }
}

final class CPUWorkload: StressWorkload {
    private let coordinator = DispatchQueue(label: "iPadBatteryExercise.cpu", qos: .userInitiated)
    private var workers: [CPUWorker]?
    private var current: WorkCancellation?

    func start(onFailure: @escaping (String) -> Void) throws {
        if workers == nil {
            let workerCount = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1))
            workers = try (0..<workerCount).map { _ in try CPUWorker() }
        }
        guard let workers = workers else { throw WorkloadError.cpuMemory }
        current?.cancel()
        let cancellation = WorkCancellation()
        current = cancellation

        // The serial coordinator prevents a new run from sharing buffers with an old run.
        coordinator.async {
            guard !cancellation.isCancelled else { return }
            let group = DispatchGroup()
            for worker in workers {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { group.leave() }
                    worker.run(until: cancellation)
                }
            }
            group.wait()
        }
    }

    func stop() {
        current?.cancel()
        current = nil
    }
}
