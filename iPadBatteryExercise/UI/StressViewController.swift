import UIKit

final class StressViewController: UIViewController {
    private let session: StressSession
    private let cpuSwitch = UISwitch()
    private let gpuSwitch = UISwitch()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let cpuUsageLabel = UILabel()
    private let panel = UIStackView()
    private let cpuUsage = AppCPUUsage()
    private var motionTimer: Timer?
    private var cpuTimer: Timer?
    private var motionStart: TimeInterval = 0

    init(session: StressSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        motionTimer?.invalidate()
        cpuTimer?.invalidate()
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.06, alpha: 1)
        configureInterface()
        session.onStateChange = { [weak self] state in self?.render(state) }
        session.onError = { [weak self] message in self?.showError(message) }
        render(session.state)
        startCPUMonitoring()
    }

    private func configureInterface() {
        cpuSwitch.isOn = true
        gpuSwitch.isOn = true
        cpuSwitch.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)
        gpuSwitch.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)

        var startStyle = UIButton.Configuration.filled()
        startStyle.title = "开始测试"
        startStyle.cornerStyle = .large
        startButton.configuration = startStyle
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        var stopStyle = UIButton.Configuration.tinted()
        stopStyle.title = "停止测试"
        stopStyle.cornerStyle = .large
        stopButton.configuration = stopStyle
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

        cpuUsageLabel.font = .preferredFont(forTextStyle: .subheadline)
        cpuUsageLabel.adjustsFontForContentSizeCategory = true
        cpuUsageLabel.textColor = .secondaryLabel
        cpuUsageLabel.textAlignment = .center
        cpuUsageLabel.text = "CPU（本 App）：—"

        statusLabel.font = .preferredFont(forTextStyle: .title2)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        let statusArea = UIView()
        statusArea.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusArea.heightAnchor.constraint(equalToConstant: 90),
            statusLabel.centerXAnchor.constraint(equalTo: statusArea.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: statusArea.centerYAnchor)
        ])

        [optionRow("CPU", toggle: cpuSwitch), optionRow("GPU", toggle: gpuSwitch),
         cpuUsageLabel, startButton, statusArea, stopButton].forEach { panel.addArrangedSubview($0) }
        panel.axis = .vertical
        panel.spacing = 24
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        let preferredWidth = panel.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.75)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            preferredWidth,
            startButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    private func optionRow(_ title: String, toggle: UISwitch) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .title3)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        toggle.accessibilityLabel = title
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        return row
    }

    private func render(_ state: StressState) {
        let isIdle = state == .idle
        cpuSwitch.isEnabled = isIdle
        gpuSwitch.isEnabled = isIdle
        startButton.isEnabled = isIdle && (cpuSwitch.isOn || gpuSwitch.isOn)
        stopButton.isEnabled = !isIdle
        stopMotion()

        switch state {
        case .idle:
            statusLabel.text = "待机"
        case .paused:
            statusLabel.text = "已暂停"
        case .running:
            statusLabel.text = "测试中"
            if !UIAccessibility.isReduceMotionEnabled {
                startMotion()
            }
        }
    }

    private func startMotion() {
        motionStart = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.movePanel() }
        }
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
    }

    private func stopMotion() {
        motionTimer?.invalidate()
        motionTimer = nil
        panel.transform = .identity
    }

    private func movePanel() {
        guard motionTimer != nil, case .running = session.state else { return }
        let safeFrame = view.safeAreaLayoutGuide.layoutFrame
        let horizontalRoom = min(panel.center.x - safeFrame.minX, safeFrame.maxX - panel.center.x)
            - panel.bounds.width / 2 - 16
        let verticalRoom = min(panel.center.y - safeFrame.minY, safeFrame.maxY - panel.center.y)
            - panel.bounds.height / 2 - 16
        let horizontalRange = max(0, min(90, horizontalRoom))
        let verticalRange = max(0, min(32, verticalRoom))
        let phase = (ProcessInfo.processInfo.systemUptime - motionStart) * 2 * .pi / 22
        // Move the view itself so its touch targets follow the visible controls.
        panel.transform = CGAffineTransform(translationX: horizontalRange * CGFloat(sin(phase)),
                                            y: verticalRange * CGFloat(sin(phase / 2)))
    }

    private func startCPUMonitoring() {
        _ = cpuUsage.sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let value = self.cpuUsage.sample() {
                    self.cpuUsageLabel.text = "CPU（本 App）：\(Int(value.rounded()))%"
                } else {
                    self.cpuUsageLabel.text = "CPU（本 App）：—"
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cpuTimer = timer
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "测试无法继续", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    @objc private func selectionChanged() { render(session.state) }
    @objc private func startTapped() { session.start(cpu: cpuSwitch.isOn, gpu: gpuSwitch.isOn) }
    @objc private func stopTapped() { session.stop() }
}
