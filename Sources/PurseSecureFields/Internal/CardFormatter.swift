enum CardFormatter {
    static func formatPAN(_ digits: String) -> String {
        let isAmex = digits.hasPrefix("34") || digits.hasPrefix("37")
        // 4-6-5 for Amex, 4-4-4-4-3 for 19-digit cards (Oney), 4-4-4-4 for standard 16-digit
        let groupSizes: [Int]
        if isAmex {
            groupSizes = [4, 6, 5]
        } else if digits.count > 16 {
            groupSizes = [4, 4, 4, 4, 3]
        } else {
            groupSizes = [4, 4, 4, 4]
        }

        var result = ""
        var idx = digits.startIndex

        for (i, size) in groupSizes.enumerated() {
            let remaining = digits.distance(from: idx, to: digits.endIndex)
            guard remaining > 0 else { break }
            let take = min(size, remaining)
            let end = digits.index(idx, offsetBy: take)
            if i > 0 { result += " " }
            result += digits[idx..<end]
            idx = end
        }
        return result
    }
}
