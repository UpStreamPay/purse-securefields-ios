import Foundation
import Testing

/// How long `waitUntil` lets a condition take before it fails the test.
///
/// Generous on purpose. Nearly every suite here is `@MainActor`, and Swift Testing starts them all
/// at once, so a stubbed gateway answer (main → URLSession → main) queues behind every other
/// test's UIKit work on the one main thread. That backlog is ~1.6 s on a laptop but has reached
/// tens of seconds on the CI runners, where a 10 s budget timed out on answers that were simply
/// late. Polling returns as soon as the condition holds, so a passing test never waits this long:
/// the timeout only bounds a test that would otherwise hang.
let waitUntilTimeout: TimeInterval = 60

/// Thrown by `waitUntil` on timeout. Swift Testing prints a thrown error on the
/// `✘ … recorded an issue` line itself (`Caught error: …`), which CI's output filter keeps,
/// whereas an `#expect` comment or `Issue.record` message goes on a continuation line it drops.
struct WaitTimeout: Error, CustomStringConvertible {
    let description: String
}

/// Polls `condition` on the main actor until it holds, instead of sleeping a fixed amount.
///
/// Throws `WaitTimeout` naming what it waited for when the condition still fails after
/// `timeout`. Throwing also ends the test there, instead of letting every later assertion fail
/// on state that never arrived.
@MainActor
func waitUntil(
    _ description: String,
    timeout: TimeInterval = waitUntilTimeout,
    _ condition: () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else {
            throw WaitTimeout(description: "timed out after \(timeout) s waiting for \(description)")
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}
