import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        configureMockIfUITesting()
        #endif
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: makeRootViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    /// `DemoUITests` always launches with `--uitesting` and expects `DemoViewController` to be
    /// the very first screen (it looks up `pan_field` etc. immediately after `app.launch()`), so
    /// that flow keeps the original root untouched. Everyday manual runs land on the bug
    /// reproduction gallery instead, with the classic demo one tap away via its nav bar button.
    private func makeRootViewController() -> UIViewController {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return DemoViewController()
        }
        return BugListViewController()
        #else
        return DemoViewController()
        #endif
    }

    #if DEBUG
    private func configureMockIfUITesting() {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        let env = ProcessInfo.processInfo.environment
        let binJSON = #"{"brands":[{"brand":"VISA","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]}]}"#
        MockURLProtocol.handlers["bin-lookup"] = .init(data: Data(binJSON.utf8), statusCode: 200)
        if let json = env["MOCK_TOKENIZE_RESPONSE"] {
            MockURLProtocol.handlers["secure-fields"] = .init(data: Data(json.utf8), statusCode: 200)
        } else if let codeStr = env["MOCK_TOKENIZE_ERROR_CODE"], let code = Int(codeStr) {
            let body = env["MOCK_TOKENIZE_ERROR_BODY"] ?? #"{"error":"Mock error"}"#
            MockURLProtocol.handlers["secure-fields"] = .init(data: Data(body.utf8), statusCode: code)
        }
    }
    #endif
}
