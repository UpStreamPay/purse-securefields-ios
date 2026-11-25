import UIKit

/// The window is built by `SceneDelegate`, not here: iOS 26 traps an app that declares a
/// `UIApplicationSceneManifest` and still creates its window from the app delegate. This one only
/// wires up the UI-test mocks, which must be in place before the scene connects.
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        configureMockIfUITesting()
        #endif
        return true
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
