import Foundation

enum RomanNumerals {
    private static let values: [(Int, String)] = [
        (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
        (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
        (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]

    /// Parses a Roman numeral (case-insensitive). Returns nil if the string
    /// contains non-numeral characters or is not consumable greedily.
    static func parse(_ s: String) -> Int? {
        let s = s.uppercased()
        guard !s.isEmpty, s.allSatisfy({ "MDCLXVI".contains($0) }) else { return nil }
        var total = 0
        var index = s.startIndex
        for (value, symbol) in values {
            while s[index...].hasPrefix(symbol) {
                total += value
                index = s.index(index, offsetBy: symbol.count)
                if index == s.endIndex { return total }
            }
        }
        return index == s.endIndex ? total : nil
    }
}
