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
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        if year > currentYear { return true }
        if year == currentYear { return month >= currentMonth }
        return false
    }
}
