import UIKit

public final class SecureBrandSelectorView: UIView {

    public var onBrandSelected: ((CardBrand) -> Void)?
    public private(set) var selectedBrand: CardBrand?

    private var brands: [CardBrand] = []

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isHidden = true
        accessibilityIdentifier = "brand_selector"
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func update(brands: [CardBrand]) {
        self.brands = brands
        rebuildChips(showBorder: brands.count > 1)
        isHidden = brands.isEmpty
    }

    private func rebuildChips(showBorder: Bool) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Preserve the user's manual selection if it survives into the new brand set; only fall
        // back to the first brand when there is no valid prior selection. Unconditionally resetting
        // to `brands.first` wiped the manual pick on every BIN lookup cycle.
        if let current = selectedBrand, brands.contains(current) {
            selectedBrand = current
        } else {
            selectedBrand = brands.first
        }

        for (index, brand) in brands.enumerated() {
            let chip = BrandChip(brand: brand, showBorder: showBorder)
            chip.tag = index
            chip.isSelected = brand == selectedBrand
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(chip)
        }
    }

    @objc private func chipTapped(_ sender: BrandChip) {
        guard sender.tag < brands.count else { return }
        let brand = brands[sender.tag]
        selectedBrand = brand
        stackView.arrangedSubviews.compactMap { $0 as? BrandChip }.forEach {
            $0.isSelected = $0.tag == sender.tag
        }
        onBrandSelected?(brand)
    }
}

// MARK: - BrandChip

private final class BrandChip: UIControl {

    override var isSelected: Bool {
        didSet {
            accessibilityTraits = isSelected ? [.button, .selected] : .button
            updateAppearance()
        }
    }

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let fallbackLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 9, weight: .semibold)
        lbl.textAlignment = .center
        lbl.adjustsFontSizeToFitWidth = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let showBorder: Bool

    init(brand: CardBrand, showBorder: Bool) {
        self.showBorder = showBorder
        super.init(frame: .zero)

        layer.cornerRadius = 4
        layer.borderWidth = showBorder ? 1 : 0
        translatesAutoresizingMaskIntoConstraints = false

        fallbackLabel.text = brand.shortName
        addSubview(imageView)
        addSubview(fallbackLabel)

        // The chip subtree contains no accessible element on its own (the image view is not
        // accessible, the fallback label is usually hidden) — without these, chips are invisible
        // to VoiceOver and unaddressable by XCUITest/Appium. The identifier derives from the
        // brand, not the index, so it stays stable across the rebuild on every BIN lookup.
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = brand.shortName
        accessibilityIdentifier = "brand_chip_\(brand.rawValue.lowercased())"

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 24),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 36),
            imageView.heightAnchor.constraint(equalToConstant: 24),
            fallbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            fallbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            fallbackLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let image = UIImage(named: brand.badgeAssetName, in: .module, compatibleWith: nil)
        if image == nil {
            // A missing badge is always a packaging defect (resource bundle not embedded in the
            // framework), never a use case — fail loudly in Debug, leave a console trace in
            // Release, then degrade to the text label.
            assertionFailure("PurseSecureFields: missing badge asset '\(brand.badgeAssetName)' — is the resource bundle embedded?")
            NSLog("PurseSecureFields: missing badge asset '%@', falling back to text label", brand.badgeAssetName)
        }
        imageView.image = image
        fallbackLabel.isHidden = image != nil
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance() {
        guard showBorder else { return }
        layer.borderColor = isSelected
            ? UIColor.systemBlue.cgColor
            : UIColor.separator.cgColor
    }
}

// MARK: - CardBrand helpers

private extension CardBrand {
    var badgeAssetName: String {
        switch self {
        case .visa:          return "visa"
        case .mastercard:    return "mastercard"
        case .amex:          return "amex"
        case .maestro:       return "maestro"
        case .carteBancaire: return "cb"
        case .oney:          return "oney"
        }
    }

    var shortName: String {
        switch self {
        case .visa:          return "Visa"
        case .mastercard:    return "Mastercard"
        case .amex:          return "American Express"
        case .maestro:       return "Maestro"
        case .carteBancaire: return "Cartes Bancaires"
        case .oney:          return "Oney"
        }
    }
}
