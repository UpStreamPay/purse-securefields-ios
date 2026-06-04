import UIKit

extension DemoViewController {

    func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        stackView.addArrangedSubview(sectionLabel("Card Number"))
        stackView.addArrangedSubview(manager.panContainer)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually

        let cvvStack = UIStackView()
        cvvStack.axis = .vertical
        cvvStack.spacing = 6
        let cvvLbl = sectionLabel("CVV")
        cvvSectionLabel = cvvLbl
        cvvStack.addArrangedSubview(cvvLbl)
        let cvvContainer = secureViewContainer(manager.cvvView)
        cvvContainerView = cvvContainer
        cvvStack.addArrangedSubview(cvvContainer)

        let expiryStack = UIStackView()
        expiryStack.axis = .vertical
        expiryStack.spacing = 6
        expiryStack.addArrangedSubview(sectionLabel("Expiry"))
        let expiryContainer = secureViewContainer(manager.expDateView)
        expiryContainerView = expiryContainer
        expiryStack.addArrangedSubview(expiryContainer)

        row.addArrangedSubview(cvvStack)
        row.addArrangedSubview(expiryStack)
        stackView.addArrangedSubview(row)

        stackView.addArrangedSubview(sectionLabel("Cardholder Name"))
        let holderContainer = secureViewContainer(manager.holderNameView)
        holderContainerView = holderContainer
        stackView.addArrangedSubview(holderContainer)

        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually
        buttonRow.addArrangedSubview(payButton)
        buttonRow.addArrangedSubview(clearButton)
        stackView.addArrangedSubview(buttonRow)
        stackView.setCustomSpacing(24, after: buttonRow)

        stackView.addArrangedSubview(divider())
        stackView.addArrangedSubview(sectionLabel("Debug"))

        let debugContainer = UIView()
        debugContainer.backgroundColor = .secondarySystemBackground
        debugContainer.layer.cornerRadius = 8
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        debugContainer.addSubview(debugLabel)
        NSLayoutConstraint.activate([
            debugLabel.topAnchor.constraint(equalTo: debugContainer.topAnchor, constant: 12),
            debugLabel.leadingAnchor.constraint(equalTo: debugContainer.leadingAnchor, constant: 12),
            debugLabel.trailingAnchor.constraint(equalTo: debugContainer.trailingAnchor, constant: -12),
            debugLabel.bottomAnchor.constraint(equalTo: debugContainer.bottomAnchor, constant: -12),
        ])
        stackView.addArrangedSubview(debugContainer)

        stackView.addArrangedSubview(divider())
        stackView.addArrangedSubview(sectionLabel("Result"))
        stackView.addArrangedSubview(resultLabel)
    }

    func sectionLabel(_ text: String) -> UILabel {
        let lbl = UILabel()
        lbl.text = text
        lbl.font = .systemFont(ofSize: 13, weight: .semibold)
        lbl.textColor = .secondaryLabel
        return lbl
    }

    func secureViewContainer(_ view: UIView) -> UIView {
        view.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 10
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.heightAnchor.constraint(equalToConstant: 48),
        ])
        return container
    }

    func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }

    func updateFieldBorders() {
        applyBorder(manager.panContainer,
                    hasContent: manager.hasFieldContent(.pan),
                    isValid: manager.isFieldValid(.pan),
                    isFocused: manager.isFieldFocused(.pan))
        applyBorder(cvvContainerView,
                    hasContent: manager.hasFieldContent(.cvv),
                    isValid: manager.isFieldValid(.cvv),
                    isFocused: manager.isFieldFocused(.cvv))
        applyBorder(expiryContainerView,
                    hasContent: manager.hasFieldContent(.expDate),
                    isValid: manager.isFieldValid(.expDate),
                    isFocused: manager.isFieldFocused(.expDate))
        applyBorder(holderContainerView,
                    hasContent: manager.hasFieldContent(.holderName),
                    isValid: manager.isFieldValid(.holderName),
                    isFocused: manager.isFieldFocused(.holderName))
    }

    private func applyBorder(_ view: UIView, hasContent: Bool, isValid: Bool, isFocused: Bool) {
        if isValid {
            view.layer.borderColor = UIColor.systemGreen.cgColor
            view.layer.borderWidth = 1.5
        } else if hasContent && !isFocused {
            view.layer.borderColor = UIColor.systemRed.cgColor
            view.layer.borderWidth = 1.5
        } else {
            view.layer.borderColor = UIColor.separator.cgColor
            view.layer.borderWidth = 1
        }
    }
}
