import UIKit

final class StressViewController: UIViewController {
    private let session: StressSession
    private let cpuSwitch = UISwitch()
    private let gpuSwitch = UISwitch()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    init(session: StressSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.06, alpha: 1)
        configureInterface()
        session.onStateChange = { [weak self] state in self?.render(state) }
        session.onError = { [weak self] message in self?.showError(message) }
        render(session.state)
    }

    private func configureInterface() {
        let title = UILabel()
        title.text = "iPad 电池测试"
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.textColor = .white

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

        let column = UIStackView(arrangedSubviews: [
            title, optionRow("CPU", toggle: cpuSwitch), optionRow("GPU", toggle: gpuSwitch),
            startButton, statusArea, stopButton
        ])
        column.axis = .vertical
        column.spacing = 24
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        let preferredWidth = column.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.75)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            column.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
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
        statusLabel.layer.removeAllAnimations()
        statusLabel.transform = .identity

        switch state {
        case .idle:
            statusLabel.text = "待机"
        case .paused:
            statusLabel.text = "已暂停"
        case .running:
            statusLabel.text = "测试中"
            if !UIAccessibility.isReduceMotionEnabled {
                UIView.animate(withDuration: 9, delay: 0,
                               options: [.autoreverse, .repeat, .allowUserInteraction, .curveEaseInOut]) {
                    self.statusLabel.transform = CGAffineTransform(translationX: 90, y: 12)
                }
            }
        }
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
