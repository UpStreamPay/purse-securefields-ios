import Foundation

enum CardValidator {
    static func luhn(_ number: String) -> Bool {
        let digits = number.compactMap { $0.wholeNumberValue }
        guard !digits.isEmpty else { return false }
        var sum = 0
        for (i, digit) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    static func isExpiryValid(month: Int, year: Int) -> Bool {
        let now = Date()
        // `parsedExpiry` always produces Gregorian years, so the "current" year/month must be read
        // from a Gregorian calendar too. Using `Calendar.current` would read e.g. 2569 on a Thai
        // Buddhist-calendar device and reject every valid card.
        let cal = Calendar(identifier: .gregorian)
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        if year > currentYear { return true }
        if year == currentYear { return month >= currentMonth }
        return false
    }
}
