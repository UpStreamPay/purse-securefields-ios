import UIKit

/// The demo's window lives here, not on `AppDelegate`.
///
/// iOS 26 traps an app that still builds its window from
/// `application(_:didFinishLaunchingWithOptions:)` while declaring a `UIApplicationSceneManifest`:
/// `_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` raises `EXC_BREAKPOINT` at
/// scene creation, before any app code runs, so the app dies on launch and every `DemoUITests`
/// case reports "com.purse.securefields.demo crashed".
///
/// `AppDelegate` keeps `didFinishLaunching` — it still runs, before the scene connects — for the
/// UI-test mock wiring only.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        // `SecureFieldsConfig` is immutable, so the app SDK configuration has to be there before
        // the form is built — exactly what a merchant app does at startup.
        Task { @MainActor in
            DemoViewController.appSDKConfiguration = await DemoBackend.appSDKConfiguration()
            DemoViewController.gatewayAPIKey = await DemoBackend.gatewayAPIKey()
            // The PSPs the "PSP" control offers.
            await DemoBackend.loadCardSolutions()
            // A navigation controller, because the mode switch swaps `DemoViewController` into
            // the stack — the whole screen is rebuilt.
            window.rootViewController = UINavigationController(rootViewController: DemoViewController())
        }
    }
}
