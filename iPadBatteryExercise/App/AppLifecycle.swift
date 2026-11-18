import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private var stressSession: StressSession?

    func session(for screen: UIScreen) -> StressSession {
        if let stressSession = stressSession { return stressSession }
        let display = ScreenPowerController(screen: screen)
        let session = StressSession(cpu: CPUWorkload(), gpu: GPUWorkload(), display: display)
        stressSession = session
        return session
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        stressSession?.stop()
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var session: StressSession?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let stressSession = appDelegate.session(for: windowScene.screen)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = StressViewController(session: stressSession)
        self.session = stressSession
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        session?.sceneDidBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        session?.sceneWillResignActive()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        session?.sceneWillResignActive()
    }
}

private final class ScreenPowerController: StressDisplay {
    private let screen: UIScreen
    private var previous: (brightness: CGFloat, idleTimerDisabled: Bool)?

    init(screen: UIScreen) {
        self.screen = screen
    }

    func enterStressMode() {
        guard previous == nil else { return }
        previous = (screen.brightness, UIApplication.shared.isIdleTimerDisabled)
        UIApplication.shared.isIdleTimerDisabled = true
        screen.brightness = 0
    }

    func restore() {
        guard let previous = previous else { return }
        screen.brightness = previous.brightness
        UIApplication.shared.isIdleTimerDisabled = previous.idleTimerDisabled
        self.previous = nil
    }
}
