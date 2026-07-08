#if DEBUG
import UIKit

/// A small scrolling, timestamped event log used by several bug screens to make delegate
/// callbacks (or their *absence*) visible on screen — several of the confirmed bugs are exactly
/// about a callback that should fire but doesn't (B7, B8) or that fires too often (B10), so a
/// human staring at the form alone can't see the bug; the log makes it explicit.
final class EventLogView: UIView {

    private let textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private var lines: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        addSubview(textView)
        heightAnchor.constraint(equalToConstant: 160).isActive = true
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        textView.text = "(aucun événement pour l'instant)"
    }

    func log(_ message: String) {
        let stamp = formatter.string(from: Date())
        lines.append("[\(stamp)] \(message)")
        textView.text = lines.joined(separator: "\n")
        let bottom = NSRange(location: (textView.text as NSString).length, length: 0)
        textView.scrollRangeToVisible(bottom)
    }

    func clear() {
        lines = []
        textView.text = "(aucun événement pour l'instant)"
    }
}

/// Tracks consecutive identical emissions of a boolean event, to make it easy to prove a
/// violation of the "only fire when the value actually flips" contract documented in AGENTS.md
/// for `secureFieldsFormValidityChanged`.
final class RepeatCounter {
    private(set) var lastValue: Bool?
    private(set) var streak = 0
    private(set) var totalEmissions = 0
    private(set) var redundantEmissions = 0

    /// Records a new emission and reports whether it repeats the previous value.
    @discardableResult
    func record(_ value: Bool) -> (isRepeat: Bool, streak: Int) {
        totalEmissions += 1
        if lastValue == value {
            streak += 1
            redundantEmissions += 1
        } else {
            streak = 1
        }
        lastValue = value
        return (streak > 1, streak)
    }

    func reset() {
        lastValue = nil
        streak = 0
        totalEmissions = 0
        redundantEmissions = 0
    }
}
#endif
