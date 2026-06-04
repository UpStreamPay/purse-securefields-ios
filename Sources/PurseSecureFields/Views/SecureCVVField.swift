import UIKit

enum CVVInputMode: Equatable {
    case cvv
    case birthdate
}

final class SecureCVVField: SecureBaseField {

    private(set) var inputMode: CVVInputMode = .cvv

    var rawValue: String { storedText ?? "" }
    var hasContent: Bool { inputMode == .birthdate || !rawValue.isEmpty }

    var expectedLength = 3 {
        didSet {
            if oldValue != expectedLength && inputMode == .cvv { textDidChange() }
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
            applyBirthdate(from: picker)
        }
    }

    @objc private func datePickerChanged(_ picker: UIDatePicker) {
        applyBirthdate(from: picker)
    }

    private func applyBirthdate(from picker: UIDatePicker) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        text = fmt.string(from: picker.date)
        onContentChanged?()
        setValidity(true)
    }

    @objc override func textDidChange() {
        guard inputMode == .cvv else { return }
        let digits = (storedText ?? "").filter { $0.isNumber }
        let truncated = String(digits.prefix(expectedLength))
        if storedText != truncated { text = truncated }
        onContentChanged?()
        setValidity(truncated.count == expectedLength)
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
