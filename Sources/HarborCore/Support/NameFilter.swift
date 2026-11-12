import Foundation

/// Type-to-filter for the panel's lists: pure, so the rule is testable without a window.
public enum NameFilter {
    /// The query's search words: trimmed, split on whitespace, lowercased and diacritic-folded.
    public static func tokens(_ query: String) -> [String] {
        self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// True when every word of `query` occurs in `name`, ignoring case and diacritics. An empty
    /// or all-whitespace query matches everything.
    public static func matches(_ name: String, query: String) -> Bool {
        let words = self.tokens(query)
        guard !words.isEmpty else { return true }
        let haystack = self.fold(name)
        return words.allSatisfy { haystack.contains($0) }
    }

    /// The items whose name matches, in their original order.
    public static func filter<T>(_ items: [T], query: String, name: (T) -> String) -> [T] {
        guard !self.tokens(query).isEmpty else { return items }
        return items.filter { self.matches(name($0), query: query) }
    }

    /// True for text a person typed to search: printable characters only. Control characters,
    /// Return, Tab, Delete and the private-use scalars AppKit sends for arrows and function
    /// keys are not search text.
    public static func isSearchText(_ characters: String) -> Bool {
        guard !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700 ... 0xF8FF).contains(scalar.value)
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
