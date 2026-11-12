import Foundation
import HarborCore
import Testing

@Suite("NameFilter")
struct NameFilterTests {
    private let repos = ["sriinnu/Harbor", "sriinnu/chitragupta", "acme/Café-api", "acme/harbor-docs", "sriinnu/Kosha"]

    @Test("an empty or blank query keeps every row, in order")
    func emptyQuery() {
        #expect(NameFilter.filter(self.repos, query: "", name: { $0 }) == self.repos)
        #expect(NameFilter.filter(self.repos, query: "   ", name: { $0 }) == self.repos)
    }

    @Test("matches are case-insensitive substrings of the full name and keep order")
    func substring() {
        #expect(NameFilter.filter(self.repos, query: "HARBOR", name: { $0 }) == ["sriinnu/Harbor", "acme/harbor-docs"])
        #expect(NameFilter.filter(self.repos, query: "acme/", name: { $0 }) == ["acme/Café-api", "acme/harbor-docs"])
    }

    @Test("every word must match, in any order")
    func words() {
        #expect(NameFilter.filter(self.repos, query: "docs acme", name: { $0 }) == ["acme/harbor-docs"])
        #expect(NameFilter.filter(self.repos, query: "docs sriinnu", name: { $0 }) == [])
    }

    @Test("diacritics are folded both ways")
    func diacritics() {
        #expect(NameFilter.filter(self.repos, query: "cafe", name: { $0 }) == ["acme/Café-api"])
        #expect(NameFilter.filter(self.repos, query: "café", name: { $0 }) == ["acme/Café-api"])
    }

    @Test("tokens are trimmed, lowercased and split on whitespace")
    func tokens() {
        #expect(NameFilter.tokens("  Foo  BAR\tbaz ") == ["foo", "bar", "baz"])
    }

    @Test("only printable characters count as search text")
    func searchText() {
        #expect(NameFilter.isSearchText("a"))
        #expect(NameFilter.isSearchText("é"))
        #expect(NameFilter.isSearchText("-"))
        #expect(!NameFilter.isSearchText(""))
        #expect(!NameFilter.isSearchText("\r"))
        #expect(!NameFilter.isSearchText("\t"))
        #expect(!NameFilter.isSearchText("\u{1B}"))
        #expect(!NameFilter.isSearchText("\u{7F}"))
        #expect(!NameFilter.isSearchText("\u{F700}")) // up arrow
    }
}
