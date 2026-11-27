public enum SecureFieldsError: Error {
    case fieldsIncomplete
    case networkError(Error)
    case apiError(message: String, statusCode: Int)
    case invalidResponse
    /// The Purse 3DS chain failed. Only ever raised on a call that asked for 3DS —
    /// `submit(threeDSEnabled: true)`, `submitSavedCard(_:)` or `challenge(_:presenting:)`.
    case threeDS(ThreeDSError)
}
