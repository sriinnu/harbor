import Foundation

// MARK: - WIQL Response

struct AzureDevOpsWiqlResponse: Decodable {
    let queryType: String?
    let queryResultType: String?
    let asOf: Date?
    let workItems: [WorkItemRef]

    struct WorkItemRef: Decodable {
        // Azure DevOps returns `id` as a JSON number; accept either form.
        let id: String
        let url: String?

        private enum Keys: String, CodingKey { case id, url }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if let n = try? c.decode(Int.self, forKey: .id) {
                self.id = String(n)
            } else {
                self.id = try c.decode(String.self, forKey: .id)
            }
            self.url = try c.decodeIfPresent(String.self, forKey: .url)
        }
    }

    enum CodingKeys: String, CodingKey {
        case queryType
        case queryResultType
        case asOf
        case workItems
    }
}
