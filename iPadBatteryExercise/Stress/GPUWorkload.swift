import Foundation
import Metal

final class GPUWorkload: StressWorkload {
    private struct Resources {
        let queue: MTLCommandQueue
        let pipeline: MTLComputePipelineState
        let buffer: MTLBuffer
    }

    private static let elementCount = 262_144
    private let coordinator = DispatchQueue(label: "iPadBatteryExercise.gpu", qos: .userInitiated)
    private var resources: Resources?
    private var current: WorkCancellation?

    func start(onFailure: @escaping (String) -> Void) throws {
        if resources == nil { resources = try prepare() }
        guard let resources = resources else { throw WorkloadError.gpuUnavailable }
        current?.cancel()
        let cancellation = WorkCancellation()
        current = cancellation

        // One serial loop and one in-flight command buffer bound both overlap and latency.
        coordinator.async {
            let width = min(resources.pipeline.maxTotalThreadsPerThreadgroup,
                            resources.pipeline.threadExecutionWidth * 4)
            let threads = MTLSize(width: Self.elementCount, height: 1, depth: 1)
            let group = MTLSize(width: width, height: 1, depth: 1)
            while !cancellation.isCancelled {
                guard let command = resources.queue.makeCommandBuffer(),
                      let encoder = command.makeComputeCommandEncoder() else {
                    Self.report("无法提交 GPU 测试任务。", cancellation, onFailure)
                    return
                }
                encoder.setComputePipelineState(resources.pipeline)
                encoder.setBuffer(resources.buffer, offset: 0, index: 0)
                encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
                encoder.endEncoding()
                guard cancellation.submitIfActive({ command.commit() }) else { return }
                command.waitUntilCompleted()
                if command.status == .error {
                    let detail = command.error?.localizedDescription ?? "未知错误"
                    Self.report("GPU 测试失败：\(detail)", cancellation, onFailure)
                    return
                }
            }
        }
    }

    func stop() {
        current?.cancel()
        current = nil
    }

    private func prepare() throws -> Resources {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw WorkloadError.gpuUnavailable }
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "stressKernel") else {
            throw WorkloadError.gpuSetup("无法加载 Metal 着色器。")
        }
        let pipeline: MTLComputePipelineState
        do {
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            throw WorkloadError.gpuSetup(error.localizedDescription)
        }
        let byteCount = Self.elementCount * MemoryLayout<SIMD4<Float>>.stride
        guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
            throw WorkloadError.gpuSetup("无法分配 GPU 缓冲区。")
        }
        memset(buffer.contents(), 0, byteCount)
        return Resources(queue: queue, pipeline: pipeline, buffer: buffer)
    }

    private static func report(_ message: String, _ cancellation: WorkCancellation,
                               _ onFailure: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            guard !cancellation.isCancelled else { return }
            onFailure(message)
        }
    }
}
