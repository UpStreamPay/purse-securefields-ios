public enum SecureFieldsError: Error {
    case fieldsIncomplete
    case networkError(Error)
    case apiError(message: String, statusCode: Int)
    case invalidResponse
}
