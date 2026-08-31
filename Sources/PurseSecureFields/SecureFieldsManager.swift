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

    /// The PAN/CVV lengths currently accepted, as driven by BIN lookup and brand selection.
    /// `.expDate` and `.holderName` carry no length constraint and return an empty array.
    public func expectedLengths(for field: SecureField) -> [Int] {
        switch field {
        case .pan:                  return panField.validLengths
        case .cvv:                  return cvvField.validLengths
        case .expDate, .holderName: return []
        }
    }

    /// Clears a single field through the same reformat/validate path as user typing, leaving the
    /// other fields untouched. `clearFields()` resets the whole form; a host offering a per-field
    /// erase button (or a test asserting what happens to the *other* fields) needs this instead.
    public func clearField(_ field: SecureField) {
        switch field {
        case .pan:
            panField.text = ""
            panField.textDidChange()
        case .cvv:
            if cvvField.inputMode == .birthdate {
                // textDidChange is a no-op in birthdate mode — clear storage and validity directly.
                cvvField.clearSensitiveData()
                delegate?.secureFieldsContentChanged()
            } else {
                cvvField.text = ""
                cvvField.textDidChange()
            }
        case .expDate:
            expDateField.text = ""
            expDateField.textDidChange()
        case .holderName:
            holderNameField.text = ""
            holderNameField.textDidChange()
        }
        notifyFormValidity()
    }

    public func clearFields() {
        binLookupWorkItem?.cancel()
        binLookupWorkItem = nil
        panField.clearSensitiveData()
        cvvField.clearSensitiveData()
        expDateField.clearSensitiveData()
        holderNameField.clearSensitiveData()
        lookupGeneration &+= 1
        lastBinPrefix = nil
        lastBinResult = nil
        detectedBrands = []
        panField.validLengths = [16]
        cvvField.validLengths = [3]
        cvvField.setInputMode(.cvv)
        brandSelectorView.update(brands: [])
        delegate?.secureFieldsBrandsDetected([])
        monitoring.recordBrandsDetected([])
        // Force the next validity notification through — the host should always hear the definitive
        // (invalid) state after a clear, even if it already believed the form invalid.
        lastNotifiedValidity = nil
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
    // Remote log monitoring — observes submit start/result via explicit hooks (below) rather
    // than tracking submit counters inline here. See MonitoringCoordinator for everything this
    // manager doesn't need to know about monitoring.
    private let monitoring: MonitoringCoordinator
    private var detectedBrands: [CardBrand] = []
    private var lastBinResult: BinLookupResult?
    private var binLookupWorkItem: DispatchWorkItem?
    private var lastBinPrefix: String?
    /// Identifies the most recently launched BIN lookup, so a response that arrives after a newer
    /// one was launched can be dropped instead of overwriting fresher brand state.
    private var lookupGeneration: UInt64 = 0

    /// Digits typed before the first BIN lookup fires.
    private static let binSize = 8
    /// Longest prefix the gateway accepts — a longer PAN produces a byte-identical request.
    private static let lookupPrefixSize = 11
    private var isSubmitting = false
    private var privacyObservers: [NSObjectProtocol] = []
    private var monitoringObservers: [NSObjectProtocol] = []

    // MARK: - Init

    public init(config: SecureFieldsConfig) {
        // Constructed and started first, using the local `config` parameter — Swift requires
        // every stored property be assigned before `self` is used, so `monitoring` (a `let`)
        // is built here and assigned to `self.monitoring` below.
        let monitoring = MonitoringCoordinator(
            tenantId: config.tenantId,
            version: VaultAPIClient.sdkVersion,
            env: config.environment.rawValue,
            monitoringApiRoot: config.environment.monitoringApiRoot,
            apiKey: config.apiKey,
            monitoringEnabled: config.monitoringEnabled
        )
        monitoring.start(config: config)
        self.monitoring = monitoring

        self.config = config
        #if DEBUG
        if let testSession = config.testURLSession {
            self.apiClient = VaultAPIClient(baseURL: config.environment.apiRoot, session: testSession)
        } else {
            self.apiClient = VaultAPIClient(baseURL: config.environment.apiRoot, pinnedPublicKeyHashes: config.pinnedPublicKeyHashes)
        }
        #else
        self.apiClient = VaultAPIClient(baseURL: config.environment.apiRoot, pinnedPublicKeyHashes: config.pinnedPublicKeyHashes)
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
        setupMonitoringObservers()
    }

    deinit {
        privacyObservers.forEach { NotificationCenter.default.removeObserver($0) }
        monitoringObservers.forEach { NotificationCenter.default.removeObserver($0) }
        monitoring.unmount()
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
        panField.onFocusChanged    = { [weak self] f in self?.focusChanged(.pan, f) }

        cvvField.onContentChanged  = { [weak self] in self?.delegate?.secureFieldsContentChanged() }
        cvvField.onValidityChanged = { [weak self] _ in self?.notifyFormValidity() }
        cvvField.onFocusChanged    = { [weak self] f in self?.focusChanged(.cvv, f) }

        expDateField.onContentChanged  = { [weak self] in self?.delegate?.secureFieldsContentChanged() }
        expDateField.onValidityChanged = { [weak self] _ in self?.notifyFormValidity() }
        expDateField.onFocusChanged    = { [weak self] f in self?.focusChanged(.expDate, f) }

        holderNameField.onContentChanged  = { [weak self] in self?.delegate?.secureFieldsContentChanged() }
        holderNameField.onValidityChanged = { [weak self] _ in self?.notifyFormValidity() }
        holderNameField.onFocusChanged    = { [weak self] f in self?.focusChanged(.holderName, f) }
    }

    private func focusChanged(_ field: SecureField, _ isFocused: Bool) {
        delegate?.secureFieldsFocusChanged(field: field, isFocused: isFocused)
        monitoring.recordFocusChanged(field: field, isFocused: isFocused)
    }

    private func setupBrandSelector() {
        brandSelectorView.onBrandSelected = { [weak self] brand in
            self?.applySelectedBrand(brand)
            self?.applyLengthsForBrand(brand)
            self?.delegate?.secureFieldsBrandSelected(brand)
            self?.monitoring.recordBrandSelected(brand)
            // Switching brand can change the CVV input mode / valid lengths (e.g. Oney birthdate),
            // which changes form validity. Recompute so the host isn't left with a stale value.
            self?.notifyFormValidity()
        }
    }

    // MARK: - BIN lookup

    private func scheduleBinLookup(digits: String) {
        binLookupWorkItem?.cancel()

        guard digits.count >= Self.binSize else {
            // Invalidate any in-flight lookup: it was requested for digits that no longer exist
            // and must not resurrect the brand state cleared just below.
            lookupGeneration &+= 1
            lastBinPrefix = nil
            if !detectedBrands.isEmpty {
                detectedBrands = []
                panField.validLengths = [16]
                cvvField.validLengths = [3]
                cvvField.setInputMode(.cvv)
                brandSelectorView.update(brands: [])
                delegate?.secureFieldsBrandsDetected([])
                monitoring.recordBrandsDetected([])
                notifyFormValidity()
            }
            return
        }

        // The gateway accepts up to 11 digits and answers on exactly what it is given, so the
        // prefix must grow with the PAN: a BIN that only becomes discriminant past 8 digits was
        // otherwise undetectable, since the 8-digit prefix never changed again and the dedupe
        // below turned every later keystroke into a no-op. Past 11 digits the request body is
        // identical, so the same dedupe correctly stops re-querying (mirrors web and Android).
        let prefix = String(digits.prefix(Self.lookupPrefixSize))
        // Skip re-querying a prefix already looked up — even when it yielded no authorized brands.
        // Gating on `!detectedBrands.isEmpty` fired a network request on every keystroke for any
        // prefix with no matching brand.
        if prefix == lastBinPrefix { return }

        lookupGeneration &+= 1
        let generation = lookupGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.apiClient.binLookup(tenantId: self.config.tenantId, firstDigits: prefix) { result in
                DispatchQueue.main.async {
                    // A lookup fires per keystroke without cancelling the one in flight, so
                    // responses can arrive out of order. Applying an older one would undo a
                    // fresher detection — clearing brands and re-narrowing the PAN length.
                    guard generation == self.lookupGeneration else { return }
                    guard case .success(let binResult) = result else {
                        // Surface the failure — silently dropping it made an outage
                        // indistinguishable from "this card has no authorized brand". The prefix
                        // is deliberately not cached, so the lookup retries on the next PAN change.
                        if case .failure(let error) = result {
                            self.delegate?.secureFieldsBinLookupFailed(error)
                            self.monitoring.recordBinLookupFailed(error)
                        }
                        return
                    }
                    let allowed = Self.allowedBrands(api: binResult.brands, config: self.config.brands)
                    self.lastBinPrefix = prefix
                    self.lastBinResult = binResult
                    self.detectedBrands = allowed
                    let fallbackPanLengths: [Int] = allowed.contains(.oney) ? [19] : [16]
                    self.panField.validLengths = binResult.panLengths.isEmpty ? fallbackPanLengths : binResult.panLengths
                    self.cvvField.validLengths = binResult.cvvLengths.isEmpty ? [3] : binResult.cvvLengths
                    self.brandSelectorView.update(brands: allowed)
                    self.applySelectedBrand(self.brandSelectorView.selectedBrand)
                    // Apply the auto-selected brand's own PAN/CVV lengths. Without this the field
                    // keeps the `is_main` brand's lengths (e.g. VISA [16]) and an auto-selected
                    // Oney card's 19-digit PAN could never validate — brand lengths were only
                    // applied on a manual chip tap.
                    if let selected = self.brandSelectorView.selectedBrand {
                        self.applyLengthsForBrand(selected)
                    }
                    self.delegate?.secureFieldsBrandsDetected(allowed)
                    self.monitoring.recordBrandsDetected(allowed)
                    self.notifyFormValidity()
                }
            }
        }
        binLookupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    /// Brands allowed for this card, in `config.brands` order. The integrator's order expresses
    /// a commercial preference (it drives the default selection), so it must win over the API
    /// response order — matching the web SDK, where `config.brands[0]` is the default brand.
    static func allowedBrands(api: [CardBrand], config: [CardBrand]) -> [CardBrand] {
        config.filter { api.contains($0) }
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
            // Screenshot detection: the OS screenshot has already been saved at this point;
            // we cannot prevent it. Notify the host so it can call clearFields() and warn
            // the cardholder. This fires after the shutter animation completes.
            nc.addObserver(forName: UIApplication.userDidTakeScreenshotNotification,
                           object: nil, queue: .main) { [weak self] _ in
                self?.delegate?.secureFieldsScreenshotDetected()
            },
        ]
    }

    /// Unlike `setupPrivacyObservers()`, these run regardless of `obscuresOnBackground` and are
    /// only ever registered once, at init — flushing buffered logs must not depend on a privacy
    /// setting the host app may turn off.
    private func setupMonitoringObservers() {
        let nc = NotificationCenter.default
        monitoringObservers = [
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.monitoring.flush() },
            nc.addObserver(forName: UIApplication.willTerminateNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.monitoring.flush() },
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

    private var lastNotifiedValidity: Bool?

    private func notifyFormValidity() {
        let valid = panField.isValid && cvvField.isValid && expDateField.isValid
            && (!config.requiresHolderName || holderNameField.isValid)
        // Emit only on a genuine state transition. Firing on every field callback produced spurious
        // `secureFieldsFormValidityChanged` events and needless host-side UI churn.
        guard valid != lastNotifiedValidity else { return }
        lastNotifiedValidity = valid
        delegate?.secureFieldsFormValidityChanged(valid)
    }

    // MARK: - Submit

    public func submit(saveToken: Bool = false) {
        guard !isSubmitting else { return }
        guard panField.isValid, cvvField.isValid, expDateField.isValid,
              !config.requiresHolderName || holderNameField.isValid else {
            delegate?.secureFieldsDidFail(.fieldsIncomplete)
            return
        }
        // Require a real brand — either the user's manual pick or an auto-detected one. Defaulting
        // to `.visa` silently tokenized non-Visa cards under the wrong network.
        guard let selectedBrand = brandSelectorView.selectedBrand ?? detectedBrands.first else {
            delegate?.secureFieldsDidFail(.fieldsIncomplete)
            return
        }
        isSubmitting = true

        // Gate on the field's actual mode, not on the brand: `selectedBrand` can resolve to Oney
        // through the `detectedBrands.first` fallback while the CVV field never switched to
        // birthdate mode — and the value it holds is then a real CVV, not a date.
        let isBirthdate = cvvField.inputMode == .birthdate
        let (month, year) = expDateField.parsedExpiry
        let holderName = holderNameField.rawValue.trimmingCharacters(in: .whitespaces)

        let payload = TokenizationPayload(
            cvv: isBirthdate ? nil : cvvField.rawValue,
            card: .init(
                pan: panField.rawValue,
                expiryMonth: month,
                expiryYear: year,
                cardHolderName: holderName.isEmpty ? nil : holderName,
                saveToken: saveToken,
                selectedNetwork: selectedBrand.rawValue
            )
        )

        // Captured before the fields are zeroed just below: the birth date is deliberately not
        // sent to the gateway and not echoed by the response, so this local is the only way it
        // can still reach the host on the result.
        let submittedBirthDate = isBirthdate ? cvvField.rawValue : nil

        // PCI compliance: raw values are copied into `payload` above — zero the field
        // buffers immediately, before the network round-trip, not on completion.
        panField.clearSensitiveData()
        cvvField.clearSensitiveData()
        expDateField.clearSensitiveData()
        holderNameField.clearSensitiveData()
        notifyFormValidity()

        monitoring.recordSubmitStart()
        apiClient.tokenize(tenantId: config.tenantId, payload: payload) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isSubmitting = false
                switch result {
                case .success(let response):
                    self.monitoring.recordSubmitSuccess()
                    let tokenResult = TokenizationResult(
                        vaultFormToken: response.formToken,
                        bin: response.card.bin,
                        lastFourDigits: response.card.lastFourDigits,
                        detectedBrands: self.detectedBrands,
                        birthDate: submittedBirthDate,
                        selectedNetwork: selectedBrand
                    )
                    // Reset brand/BIN state after a successful tokenization (fields were already
                    // zeroed at submit). Otherwise stale `detectedBrands`/`selectedBrand`/lengths
                    // bleed into the next transaction. Built `tokenResult` first so it still
                    // carries the brands from this transaction.
                    self.clearFields()
                    self.delegate?.secureFieldsDidTokenize(tokenResult)
                case .failure(let error):
                    self.monitoring.recordSubmitFailure(error)
                    self.delegate?.secureFieldsDidFail(error)
                }
            }
        }
    }
}
