public struct TokenizationResult {
    public let vaultFormToken: String

    /// The card's BIN and last four digits as echoed by the gateway. Both are `nil` after a
    /// **CVV-only** tokenization (`SecureFieldsFieldsConfig` without `pan`): the vault stored a
    /// cryptogram against a card it already knows, so the response carries no `card` block.
    /// Mirrors `SubmitResult.Success.card == null` on Android.
    public let bin: String?
    public let lastFourDigits: String?

    /// Brands detected by BIN lookup — empty on a CVV-only form, which never looks up a BIN.
    public let detectedBrands: [CardBrand]

    /// The birth date submitted on an Oney flow, `"yyyy-MM-dd"` — nil for every other brand.
    ///
    /// Reflected from the SDK's own state, not from the response: the date never reaches the
    /// gateway (see `TokenizationPayload`), so this is the only place an integrator can read
    /// back what the cardholder picked. Mirrors `SubmitResult.Success.birthDate` on Android and
    /// `birth_date` on web.
    public let birthDate: String?

    /// The network actually submitted as `selected_network` — the cardholder's pick on a
    /// co-badged card, otherwise the auto-selected brand. Neither the response nor the request
    /// echo is readable by the host, so the SDK surfaces it here. `nil` on a CVV-only form,
    /// which submits no network at all.
    public let selectedNetwork: CardBrand?

    public init(
        vaultFormToken: String,
        bin: String?,
        lastFourDigits: String?,
        detectedBrands: [CardBrand],
        birthDate: String? = nil,
        selectedNetwork: CardBrand? = nil
    ) {
        self.vaultFormToken = vaultFormToken
        self.bin = bin
        self.lastFourDigits = lastFourDigits
        self.detectedBrands = detectedBrands
        self.birthDate = birthDate
        self.selectedNetwork = selectedNetwork
    }
}
