import Foundation
import UIKit

public final class SecureFieldsManager {

    // MARK: - Public views (opaque — host app cannot read card data from these)

    public let panContainer: SecurePANContainer
    public var cvvView: UIView { cvvField }
    public var expDateView: UIView { expDateField }
    public var holderNameView: UIView { holderNameField }

    // MARK: - Internal fields

    private let holderNameField: SecureHolderNameField
    private let panField: SecurePANField
    private let cvvField: SecureCVVField
    private let expDateField: SecureExpDateField
    private let brandSelectorView = SecureBrandSelectorView()

    // MARK: - Public

    public weak var delegate: SecureFieldsDelegate?

    /// Number of PAN digits typed. Useful for debug/UI without exposing the actual PAN.
    public var panDigitCount: Int { panField.rawValue.count }

    public func isFieldValid(_ field: SecureField) -> Bool {
        switch field {
        case .pan:        return panField.isValid
        case .cvv:        return cvvField.isValid
        case .expDate:    return expDateField.isValid
        case .holderName: return holderNameField.isValid
        }
    }

    public func isFieldFocused(_ field: SecureField) -> Bool {
        switch field {
        case .pan:        return panField.isFirstResponder
        case .cvv:        return cvvField.isFirstResponder
        case .expDate:    return expDateField.isFirstResponder
        case .holderName: return holderNameField.isFirstResponder
        }
    }

    public func hasFieldContent(_ field: SecureField) -> Bool {
        switch field {
        case .pan:        return panField.hasContent
        case .cvv:        return cvvField.hasContent
        case .expDate:    return expDateField.hasContent
        case .holderName: return holderNameField.hasContent
        }
    }

    public func clearFields() {
        binLookupWorkItem?.cancel()
        binLookupWorkItem = nil
        panField.clearSensitiveData()
        cvvField.clearSensitiveData()
        expDateField.clearSensitiveData()
        holderNameField.clearSensitiveData()
        lastBinPrefix = nil
        lastBinResult = nil
        detectedBrands = []
        panField.validLengths = [16]
        cvvField.validLengths = [3]
        cvvField.setInputMode(.cvv)
        brandSelectorView.update(brands: [])
        delegate?.secureFieldsBrandsDetected([])
        notifyFormValidity()
    }

    // MARK: - Private state

    /// When true (default), secure fields are blurred while the app is backgrounded
    /// or a screen recording is active.
    public var obscuresOnBackground = true {
        didSet { setupPrivacyObservers() }
    }

    private let config: SecureFieldsConfig
    private let apiClient: VaultAPIClient
    private var detectedBrands: [CardBrand] = []
    private var lastBinResult: BinLookupResult?
    private var binLookupWorkItem: DispatchWorkItem?
    private var lastBinPrefix: String?
    private var isSubmitting = false
    private var privacyObservers: [NSObjectProtocol] = []

    // MARK: - Init

    public init(config: SecureFieldsConfig) {
        self.config = config
        #if DEBUG
        if let testSession = config.testURLSession {
            self.apiClient = VaultAPIClient(baseURL: config.baseURL, session: testSession)
        } else {
            self.apiClient = VaultAPIClient(baseURL: config.baseURL)
        }
        #else
        self.apiClient = VaultAPIClient(baseURL: config.baseURL)
        #endif
        let pan = SecurePANField()
        let cvv = SecureCVVField()
        let exp = SecureExpDateField()
        let holder = SecureHolderNameField()
        self.panField = pan
        self.cvvField = cvv
        self.expDateField = exp
        self.holderNameField = holder
        self.panContainer = SecurePANContainer(panField: pan, brandSelectorView: brandSelectorView)
        setupFieldCallbacks()
        setupBrandSelector()
        applyConfig(config)
        setupPrivacyObservers()
    }

    // MARK: - Config

    private func applyConfig(_ config: SecureFieldsConfig) {
        let style = config.style
        let ph = config.placeholders
        for field in [panField, cvvField as SecureBaseField, expDateField, holderNameField] {
            field.applyStyle(style)
        }
        panField.applyPlaceholder(ph.pan, color: style.placeholderColor)
        cvvField.applyPlaceholder(ph.cvv, color: style.placeholderColor)
        expDateField.applyPlaceholder(ph.expDate, color: style.placeholderColor)
        holderNameField.applyPlaceholder(ph.holderName, color: style.placeholderColor)
    }

    // MARK: - Callbacks

    private func setupFieldCallbacks() {
        panField.onDigitsChanged = { [weak self] digits in
            self?.scheduleBinLookup(digits: digits)
            self?.delegate?.secureFieldsContentChanged()
        }
        panField.onValidityChanged = { [weak self] _ in self?.notifyFormValidity() }
        panField.onFocusChanged    = { [weak self] f in self?.delegate?.secureFieldsFocusChanged(field: .pan, isFocused: f) }

        cvvField.onContentChanged  = { [weak self] in self?.delegate?.secureFieldsContentChanged() }
        cvvField.onValidityChanged = { [weak self] _ in self?.notifyFormValidity() }
        cvvField.onFocusChanged    = { [weak self] f in self?.delegate?.secureFieldsFocusChanged(field: .cvv, isFocused: f) }

        expDateField.onContentChanged  = { [weak self] in self?.delegate?.secureFieldsContentChanged() }
        expDateField.onValidityChanged = { [weak self] _ in self?.notifyFormValidity() }
        expDateField.onFocusChanged    = { [weak self] f in self?.delegate?.secureFieldsFocusChanged(field: .expDate, isFocused: f) }

        holderNameField.onContentChanged  = { [weak self] in self?.delegate?.secureFieldsContentChanged() }
        holderNameField.onValidityChanged = { [weak self] _ in self?.notifyFormValidity() }
        holderNameField.onFocusChanged    = { [weak self] f in self?.delegate?.secureFieldsFocusChanged(field: .holderName, isFocused: f) }
    }

    private func setupBrandSelector() {
        brandSelectorView.onBrandSelected = { [weak self] brand in
            self?.applySelectedBrand(brand)
            self?.applyLengthsForBrand(brand)
            self?.delegate?.secureFieldsBrandSelected(brand)
        }
    }

    // MARK: - BIN lookup

    private func scheduleBinLookup(digits: String) {
        binLookupWorkItem?.cancel()

        guard digits.count >= 6 else {
            if !detectedBrands.isEmpty {
                lastBinPrefix = nil
                detectedBrands = []
                panField.validLengths = [16]
                cvvField.validLengths = [3]
                cvvField.setInputMode(.cvv)
                brandSelectorView.update(brands: [])
                delegate?.secureFieldsBrandsDetected([])
                notifyFormValidity()
            }
            return
        }

        let prefix = String(digits.prefix(8))
        if prefix == lastBinPrefix && !detectedBrands.isEmpty { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.apiClient.binLookup(tenantId: self.config.tenantId, firstDigits: prefix) { result in
                DispatchQueue.main.async {
                    guard case .success(let binResult) = result else { return }
                    guard prefix == String(self.panField.rawValue.prefix(8)) else { return }
                    let allowed = binResult.brands.filter { self.config.brands.contains($0) }
                    self.lastBinPrefix = prefix
                    self.lastBinResult = binResult
                    self.detectedBrands = allowed
                    let fallbackPanLengths: [Int] = allowed.contains(.oney) ? [19] : [16]
                    self.panField.validLengths = binResult.panLengths.isEmpty ? fallbackPanLengths : binResult.panLengths
                    self.cvvField.validLengths = binResult.cvvLengths.isEmpty ? [3] : binResult.cvvLengths
                    self.brandSelectorView.update(brands: allowed)
                    self.applySelectedBrand(self.brandSelectorView.selectedBrand)
                    self.delegate?.secureFieldsBrandsDetected(allowed)
                    self.notifyFormValidity()
                }
            }
        }
        binLookupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func applySelectedBrand(_ brand: CardBrand?) {
        cvvField.setInputMode(brand == .oney ? .birthdate : .cvv)
    }

    private func applyLengthsForBrand(_ brand: CardBrand) {
        guard let lengths = lastBinResult?.perBrandLengths[brand] else { return }
        if !lengths.panLengths.isEmpty { panField.validLengths = lengths.panLengths }
        if !lengths.cvvLengths.isEmpty { cvvField.validLengths = lengths.cvvLengths }
    }

    private func setupPrivacyObservers() {
        privacyObservers.forEach { NotificationCenter.default.removeObserver($0) }
        privacyObservers = []
        guard obscuresOnBackground else { return }

        let nc = NotificationCenter.default
        privacyObservers = [
            nc.addObserver(forName: UIApplication.willResignActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.setPrivacyOverlay(true) },
            nc.addObserver(forName: UIApplication.didBecomeActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.setPrivacyOverlay(false) },
            nc.addObserver(forName: UIScreen.capturedDidChangeNotification,
                           object: nil, queue: .main) { [weak self] _ in
                self?.setPrivacyOverlay(UIScreen.main.isCaptured)
            },
        ]
    }

    private func setPrivacyOverlay(_ show: Bool) {
        let views: [UIView] = [panContainer, cvvView, expDateView, holderNameView]
        for view in views {
            if show {
                guard view.viewWithTag(0xC1A) == nil else { continue }
                let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
                blur.tag = 0xC1A
                blur.frame = view.bounds
                blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(blur)
            } else {
                view.viewWithTag(0xC1A)?.removeFromSuperview()
            }
        }
    }

    private func notifyFormValidity() {
        let valid = panField.isValid && cvvField.isValid && expDateField.isValid
        delegate?.secureFieldsFormValidityChanged(valid)
    }

    // MARK: - Submit

    public func submit(saveToken: Bool = false) {
        guard !isSubmitting else { return }
        guard panField.isValid, cvvField.isValid, expDateField.isValid else {
            delegate?.secureFieldsDidFail(.fieldsIncomplete)
            return
        }
        isSubmitting = true

        let selectedBrand = brandSelectorView.selectedBrand ?? detectedBrands.first ?? .visa
        let isOney = selectedBrand == .oney
        let (month, year) = expDateField.parsedExpiry
        let holderName = holderNameField.rawValue.trimmingCharacters(in: .whitespaces)

        let payload = TokenizationPayload(
            cvv: isOney ? nil : cvvField.rawValue,
            birthDate: isOney ? cvvField.rawValue : nil,
            card: .init(
                pan: panField.rawValue,
                expiryMonth: month,
                expiryYear: year,
                cardHolderName: holderName.isEmpty ? nil : holderName,
                saveToken: saveToken,
                selectedNetwork: selectedBrand.rawValue
            )
        )

        apiClient.tokenize(tenantId: config.tenantId, payload: payload) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isSubmitting = false
                switch result {
                case .success(let response):
                    let tokenResult = TokenizationResult(
                        vaultFormToken: response.formToken,
                        bin: response.card.bin,
                        lastFourDigits: response.card.lastFourDigits,
                        detectedBrands: self.detectedBrands
                    )
                    self.delegate?.secureFieldsDidTokenize(tokenResult)
                case .failure(let error):
                    self.delegate?.secureFieldsDidFail(error)
                }
            }
        }
    }
}
