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

    /// The fields this form renders, as declared by `SecureFieldsConfig.fields`. Always contains
    /// `.cvv`. A field outside this set is hidden, ignored by form validity and by `submit()`.
    /// Mount only these views. Mirrors `configuredFields` on Android.
    public let configuredFields: Set<SecureField>

    /// True when the form has no PAN field: `submit()` then tokenizes the CVV alone, against a
    /// card the vault already holds, and the request carries no `card` block at all.
    public var isCVVOnly: Bool { !configuredFields.contains(.pan) }

    /// The brand currently driving the form: on a full form, the cardholder's pick on the
    /// selector or the auto-selected detected brand; on a CVV-only form, the brand named through
    /// `selectBrand(_:)`, or `nil` while none has been.
    public var selectedBrand: CardBrand? {
        isCVVOnly ? cvvOnlySelectedBrand : brandSelectorView.selectedBrand
    }

    /// Names the card's brand from the host's own knowledge or UI. Mirrors `setBrandSelection`
    /// on Android.
    ///
    /// - On a **CVV-only** form this is how the SDK learns which CVV length to expect, since
    ///   there is no PAN to look up: the field narrows to that brand's length — 4 digits for
    ///   Amex, 3 otherwise — `expectedLengths(for: .cvv)` reflects it, and a typed CVV of the
    ///   wrong length becomes invalid (kept, not truncated). The choice survives `clearFields()`
    ///   and a successful `submit()`: the saved card does not change between attempts. Oney is
    ///   refused with a warning — its birthdate flow is not available on a CVV-only form.
    /// - On a **full** form it acts exactly like a tap on the brand selector chip, whether or not
    ///   the selector is shown, and is refused when the BIN lookup did not announce that brand.
    ///
    /// Fires `secureFieldsBrandSelected(_:)` when the selection is applied.
    public func selectBrand(_ brand: CardBrand) {
        if isCVVOnly {
            guard let lengths = brand.standingCVVLengths else {
                NSLog("PurseSecureFields: selectBrand(.oney) ignored — the Oney birthdate flow is not available on a CVV-only form")
                return
            }
            cvvOnlySelectedBrand = brand
            cvvField.validLengths = lengths
            delegate?.secureFieldsBrandSelected(brand)
            monitoring.recordBrandSelected(brand)
            notifyFormValidity()
            return
        }
        guard detectedBrands.contains(brand) else {
            NSLog("PurseSecureFields: selectBrand('%@') ignored — this brand was not detected on the card", brand.rawValue)
            return
        }
        brandSelectorView.select(brand)
    }

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
        cvvField.validLengths = defaultCVVLengths
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
    /// CVV-only: the brand the host named through `selectBrand(_:)`, standing in for the BIN
    /// lookup a form without a PAN field can never run.
    private var cvvOnlySelectedBrand: CardBrand?
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
        // `.test` is internal-only and is refused in a release-signed host app, whatever the
        // merchant passed — the SDK ships as one binary for every build type, so the check can
        // only be a runtime one (mirrors Android's resolveEnvironment).
        let environment = VaultEnvironment.resolve(config.environment, isDebugHost: VaultEnvironment.isDebugHost)

        // Constructed and started first, using the local `config` parameter — Swift requires
        // every stored property be assigned before `self` is used, so `monitoring` (a `let`)
        // is built here and assigned to `self.monitoring` below.
        let monitoring = MonitoringCoordinator(
            tenantId: config.tenantId,
            version: VaultAPIClient.sdkVersion,
            env: environment.rawValue,
            monitoringApiRoot: environment.monitoringApiRoot,
            apiKey: config.apiKey,
            monitoringEnabled: config.monitoringEnabled
        )
        monitoring.start(config: config)
        self.monitoring = monitoring

        self.config = config
        self.configuredFields = config.fields.configuredFields
        if let overrideSession = config.urlSessionOverride {
            self.apiClient = VaultAPIClient(baseURL: environment.apiRoot, session: overrideSession)
        } else {
            self.apiClient = VaultAPIClient(baseURL: environment.apiRoot, pinnedPublicKeyHashes: config.pinnedPublicKeyHashes)
        }
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
        let legacyPlaceholders: [SecureField: String] = [
            .pan: ph.pan, .cvv: ph.cvv, .expDate: ph.expDate, .holderName: ph.holderName,
        ]
        let fields: [(SecureField, SecureBaseField)] = [
            (.pan, panField), (.cvv, cvvField), (.expDate, expDateField), (.holderName, holderNameField),
        ]
        for (name, field) in fields {
            field.applyStyle(style)
            let perField = config.fields.config(for: name)
            field.applyPlaceholder(perField?.placeholder ?? legacyPlaceholders[name]!, color: style.placeholderColor)
            field.accessibilityLabel = perField?.accessibilityLabel
        }
        // A field left out of `fields` is not part of the form. It is still constructed — the
        // state accessors above answer for it (`isFieldValid(.pan)` is simply false, and
        // `panDigitCount` is 0) — but it is hidden and inert, so a host that mounts it anyway
        // cannot collect data the form will never submit.
        let optionalViews: [(SecureField, UIView)] = [
            (.pan, panContainer), (.expDate, expDateView), (.holderName, holderNameView),
        ]
        for (name, view) in optionalViews where !configuredFields.contains(name) {
            view.isHidden = true
            view.isUserInteractionEnabled = false
        }
        // No PAN field means no BIN lookup: the CVV length comes from the brands the host
        // configured instead (see `CardBrand.cvvOnlyLengths`), or later from `selectBrand(_:)`.
        cvvField.validLengths = defaultCVVLengths
    }

    /// The CVV lengths accepted while the BIN lookup has not answered. `[3]` on a form with a PAN
    /// field — the lookup refines it as soon as the cardholder types. On a CVV-only form, which
    /// has nothing to look up: the brand named through `selectBrand(_:)` if any, else what the
    /// configured `brands` allow — one brand its exact length, several the union, none `[3, 4]`.
    private var defaultCVVLengths: [Int] {
        guard isCVVOnly else { return [3] }
        if let lengths = cvvOnlySelectedBrand?.standingCVVLengths { return lengths }
        return CardBrand.cvvOnlyLengths(for: config.brands)
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
        brandSelectorView.isSelectorEnabled = config.brandSelector
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
                cvvField.validLengths = defaultCVVLengths
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

    /// The network to submit, arbitrating between the merchant's `submit(selectedNetwork:)` and
    /// the SDK's own resolution. The cardholder's choice outranks the merchant's (Android does
    /// the same), and a network this card doesn't carry is refused rather than tokenized under a
    /// brand the BIN never announced.
    static func effectiveNetwork(
        requested: CardBrand?,
        resolved: CardBrand,
        detected: [CardBrand],
        brandSelectorEnabled: Bool
    ) -> CardBrand {
        guard let requested else { return resolved }
        if brandSelectorEnabled {
            NSLog("PurseSecureFields: selectedNetwork ignored — brandSelector is enabled, the cardholder's selection wins")
            return resolved
        }
        guard detected.contains(requested) else {
            NSLog("PurseSecureFields: selectedNetwork '%@' was not detected on this card — submitting '%@'",
                  requested.rawValue, resolved.rawValue)
            return resolved
        }
        return requested
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

    /// The fields whose validity gates the form: every configured field, except the cardholder
    /// name unless `requiresHolderName` opts it in — it is optional at tokenization.
    private var fieldsGatingValidity: [SecureBaseField] {
        var fields: [SecureBaseField] = [cvvField]
        if configuredFields.contains(.pan) { fields.append(panField) }
        if configuredFields.contains(.expDate) { fields.append(expDateField) }
        if configuredFields.contains(.holderName) && config.requiresHolderName { fields.append(holderNameField) }
        return fields
    }

    private func notifyFormValidity() {
        let valid = fieldsGatingValidity.allSatisfy(\.isValid)
        // Emit only on a genuine state transition. Firing on every field callback produced spurious
        // `secureFieldsFormValidityChanged` events and needless host-side UI churn.
        guard valid != lastNotifiedValidity else { return }
        lastNotifiedValidity = valid
        delegate?.secureFieldsFormValidityChanged(valid)
    }

    // MARK: - Submit

    /// Tokenizes the form.
    ///
    /// - Parameters:
    ///   - selectedNetwork: the network to submit for a co-badged card, overriding the SDK's own
    ///     resolution. Ignored — with a warning — when `SecureFieldsConfig.brandSelector` is
    ///     enabled, since the cardholder's pick then wins; and ignored when the brand was not
    ///     detected on this card, rather than tokenizing under a network the BIN doesn't carry.
    ///     Mirrors `SubmitOptions.selectedNetwork` on Android.
    ///   - saveToken: asks the vault to retain the card for later reuse.
    ///
    /// On a **CVV-only** form (no `pan` in `SecureFieldsConfig.fields`) both parameters are
    /// ignored with a warning: they describe the `card` block, and a CVV-only request carries
    /// none — the body is `{"cvv": "…"}` alone, as on web and Android. The result then has no
    /// `bin`, `lastFourDigits` or `selectedNetwork`.
    public func submit(selectedNetwork: CardBrand? = nil, saveToken: Bool = false) {
        guard !isSubmitting else { return }
        guard fieldsGatingValidity.allSatisfy(\.isValid) else {
            delegate?.secureFieldsDidFail(.fieldsIncomplete)
            return
        }

        let card: TokenizationPayload.CardPayload?
        let selectedBrand: CardBrand?
        if isCVVOnly {
            if selectedNetwork != nil || saveToken {
                NSLog("PurseSecureFields: selectedNetwork/saveToken ignored — a CVV-only form submits no card")
            }
            card = nil
            selectedBrand = nil
        } else {
            // Require a real brand — either the user's manual pick or an auto-detected one.
            // Defaulting to `.visa` silently tokenized non-Visa cards under the wrong network.
            guard let resolvedBrand = brandSelectorView.selectedBrand ?? detectedBrands.first else {
                delegate?.secureFieldsDidFail(.fieldsIncomplete)
                return
            }
            let brand = Self.effectiveNetwork(
                requested: selectedNetwork,
                resolved: resolvedBrand,
                detected: detectedBrands,
                brandSelectorEnabled: config.brandSelector
            )
            let (month, year) = expDateField.parsedExpiry
            let holderName = holderNameField.rawValue.trimmingCharacters(in: .whitespaces)
            card = .init(
                pan: panField.rawValue,
                expiryMonth: month,
                expiryYear: year,
                cardHolderName: holderName.isEmpty ? nil : holderName,
                saveToken: saveToken,
                selectedNetwork: brand.rawValue
            )
            selectedBrand = brand
        }
        isSubmitting = true

        // Gate on the field's actual mode, not on the brand: `selectedBrand` can resolve to Oney
        // through the `detectedBrands.first` fallback while the CVV field never switched to
        // birthdate mode — and the value it holds is then a real CVV, not a date.
        let isBirthdate = cvvField.inputMode == .birthdate

        let payload = TokenizationPayload(cvv: isBirthdate ? nil : cvvField.rawValue, card: card)

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
                        bin: response.card?.bin,
                        lastFourDigits: response.card?.lastFourDigits,
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
