import UIKit

public final class SecurePANContainer: UIView {

    private let panField: SecurePANField
    private let brandSelectorView: SecureBrandSelectorView

    init(panField: SecurePANField, brandSelectorView: SecureBrandSelectorView) {
        self.panField = panField
        self.brandSelectorView = brandSelectorView
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 10

        panField.translatesAutoresizingMaskIntoConstraints = false
        panField.borderStyle = .none
        brandSelectorView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(panField)
        addSubview(brandSelectorView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),

            panField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            panField.centerYAnchor.constraint(equalTo: centerYAnchor),
            panField.trailingAnchor.constraint(equalTo: brandSelectorView.leadingAnchor, constant: -8),

            brandSelectorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            brandSelectorView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
