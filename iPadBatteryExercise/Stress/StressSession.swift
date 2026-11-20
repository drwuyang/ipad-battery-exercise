import Foundation

struct WorkloadSelection: Equatable {
    let cpu: Bool
    let gpu: Bool

    static let defaultSelection = WorkloadSelection(cpu: true, gpu: true)
}

enum StressState: Equatable {
    case idle
    case running(WorkloadSelection)
    case paused(WorkloadSelection)
}

// Session methods and failure callbacks are invoked on the main thread.
protocol StressWorkload: AnyObject {
    func start(onFailure: @escaping (String) -> Void) throws
    func stop()
}

@MainActor
protocol StressDisplay: AnyObject {
    func enterStressMode()
    func restore()
}

@MainActor
final class StressSession {
    private let cpu: StressWorkload
    private let gpu: StressWorkload
    private let display: StressDisplay
    private var sceneIsActive = false
    private var isFirstActivation = true
    private var runID: UUID?

    private(set) var state: StressState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((StressState) -> Void)?
    var onError: ((String) -> Void)?

    init(cpu: StressWorkload, gpu: StressWorkload, display: StressDisplay) {
        self.cpu = cpu
        self.gpu = gpu
        self.display = display
    }

    func start(cpu: Bool, gpu: Bool) {
        guard sceneIsActive, state == .idle, cpu || gpu else { return }
        run(WorkloadSelection(cpu: cpu, gpu: gpu))
    }

    func stop() {
        switch state {
        case .idle:
            return
        case .running:
            cancelWork()
            display.restore()
        case .paused:
            break
        }
        state = .idle
    }

    func sceneWillResignActive() {
        sceneIsActive = false
        guard case let .running(selection) = state else { return }
        cancelWork()
        display.restore()
        state = .paused(selection)
    }

    func sceneDidBecomeActive() {
        sceneIsActive = true
        if isFirstActivation {
            isFirstActivation = false
            run(.defaultSelection)
            return
        }
        guard case let .paused(selection) = state else { return }
        run(selection)
    }

    private func run(_ selection: WorkloadSelection) {
        let id = UUID()
        runID = id
        let failure: (String) -> Void = { [weak self] message in
            guard let self = self, self.runID == id else { return }
            self.stop()
            self.onError?(message)
        }

        do {
            if selection.cpu { try cpu.start(onFailure: failure) }
            if selection.gpu { try gpu.start(onFailure: failure) }
            display.enterStressMode()
            state = .running(selection)
        } catch {
            cancelWork()
            state = .idle
            onError?(error.localizedDescription)
        }
    }

    private func cancelWork() {
        runID = nil
        cpu.stop()
        gpu.stop()
    }
}
