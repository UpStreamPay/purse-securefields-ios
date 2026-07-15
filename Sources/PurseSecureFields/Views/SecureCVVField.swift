import UIKit

enum CVVInputMode: Equatable {
    case cvv
    case birthdate
}

final class SecureCVVField: SecureBaseField {

    private(set) var inputMode: CVVInputMode = .cvv

    var rawValue: String { storedText ?? "" }
    var hasContent: Bool { inputMode == .birthdate || !rawValue.isEmpty }

    var validLengths: [Int] = [3] {
        didSet {
            if oldValue != validLengths && inputMode == .cvv { textDidChange() }
        }
    }

    override func setup() {
        super.setup()
        keyboardType = .numberPad
        autocorrectionType = .no
        isSecureTextEntry = true
    }

    func setInputMode(_ mode: CVVInputMode) {
        guard mode != inputMode else { return }
        inputMode = mode
        clearSensitiveData()
        configureForMode()
    }

    private func configureForMode() {
        switch inputMode {
        case .cvv:
            inputView = nil
            inputAccessoryView = nil
            isSecureTextEntry = true
            reloadInputViews()
            // The field was just cleared switching out of birthdate mode — recompute validity so a
            // stale `isValid == true` from the previous mode does not leak into the form state.
            textDidChange()

        case .birthdate:
            let picker = UIDatePicker()
            picker.datePickerMode = .date
            if #available(iOS 13.4, *) {
                picker.preferredDatePickerStyle = .wheels
            }
            picker.maximumDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            picker.addTarget(self, action: #selector(datePickerChanged(_:)), for: .valueChanged)
            inputView = picker
            inputAccessoryView = makeDoneToolbar()
            isSecureTextEntry = false
            reloadInputViews()
            // Do NOT pre-fill the birth date. Leaving it empty + invalid forces an explicit user
            // pick before the form can submit — auto-populating "yesterday" let a wrong birth date
            // be submitted with no user interaction.
            setValidity(false)
        }
    }

    @objc private func datePickerChanged(_ picker: UIDatePicker) {
        applyBirthdate(from: picker)
    }

    private func applyBirthdate(from picker: UIDatePicker) {
        let fmt = DateFormatter()
        // Pin locale + calendar so the output is always Gregorian ISO `yyyy-MM-dd`, regardless of
        // device settings. Without this, a Buddhist-calendar device emits e.g. `2569-…`, which the
        // backend rejects.
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd"
        text = fmt.string(from: picker.date)
        onContentChanged?()
        setValidity(true)
    }

    @objc override func textDidChange() {
        guard inputMode == .cvv else { return }
        let digits = (storedText ?? "").filter { $0.isNumber }
        let maxLen = validLengths.max() ?? 4
        let truncated = String(digits.prefix(maxLen))
        if storedText != truncated { text = truncated }
        onContentChanged?()
        setValidity(validLengths.contains(truncated.count))
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if inputMode == .cvv && action == #selector(paste(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    private func makeDoneToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissPicker))
        toolbar.items = [space, done]
        return toolbar
    }

    @objc private func dismissPicker() {
        resignFirstResponder()
    }
}
