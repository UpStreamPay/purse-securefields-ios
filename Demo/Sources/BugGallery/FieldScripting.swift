#if DEBUG
import UIKit

/// Demo-only plumbing that lets a bug screen script deterministic keystrokes into the SDK's
/// secure fields, instead of relying on a human typing at exactly the right speed or placing the
/// text cursor by hand. This does NOT bypass the SDK's PCI field isolation: `SecureBaseField`
/// still blocks reading `.text`/`.attributedText`/`.accessibilityValue` (see AGENTS.md) — these
/// helpers only *write* (via the same `UIControl` target-action path a real keystroke uses) or
/// read UIKit-only properties like `selectedTextRange` that were never blocked.
extension UIView {
    /// Depth-first search for the first `UITextField` in this view's subview hierarchy. The
    /// secure fields are only exposed to host apps as opaque `UIView`s (`cvvView`, `expDateView`,
    /// `holderNameView`) or nested inside `SecurePANContainer` — but their *runtime* type is
    /// still a `UITextField` subclass, so a dynamic cast still finds it.
    func firstTextField() -> UITextField? {
        if let tf = self as? UITextField { return tf }
        for sub in subviews {
            if let match = sub.firstTextField() { return match }
        }
        return nil
    }
}

extension UITextField {
    /// Sets `text` and fires `.editingChanged`, exactly as UIKit does after a real keystroke —
    /// this drives the SDK's own `textDidChange()` override (formatting, validity, BIN lookup
    /// scheduling) without needing an actual keyboard event.
    func simulateTyping(_ text: String) {
        self.text = text
        sendActions(for: .editingChanged)
    }

    /// Same idea, but appends `full` one character at a time with `delay` between keystrokes so
    /// debounced logic (e.g. the SDK's 300ms BIN-lookup debounce) has time to settle between each
    /// one. Needed to reproduce bugs that depend on *multiple distinct* BIN lookups completing,
    /// rather than a single lookup after the last character lands.
    func simulateTypingWithDelay(
        _ full: String,
        delay: TimeInterval,
        onEachCharacter: ((String) -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        var index = full.startIndex
        var current = ""
        func step() {
            guard index < full.endIndex else { completion?(); return }
            current.append(full[index])
            index = full.index(after: index)
            self.simulateTyping(current)
            onEachCharacter?(current)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
        }
        step()
    }

    /// Offset (in UTF-16 code units) of the caret from the start of the field — used to make the
    /// "cursor forced to the end" bug (B6) visible without needing to read the field's actual text.
    var caretOffsetFromStart: Int? {
        guard let range = selectedTextRange else { return nil }
        return offset(from: beginningOfDocument, to: range.start)
    }

    func moveCaret(toOffset targetOffset: Int) {
        guard let position = position(from: beginningOfDocument, offset: targetOffset) else { return }
        selectedTextRange = textRange(from: position, to: position)
    }
}
#endif
