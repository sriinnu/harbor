import Foundation

// MARK: - WIQL Response

struct AzureDevOpsWiqlResponse: Decodable {
    let queryType: String?
    let queryResultType: String?
    let asOf: Date?
    let workItems: [WorkItemRef]

    struct WorkItemRef: Decodable {
        let id: String
        let url: String?
    }

    enum CodingKeys: String, CodingKey {
        case queryType
        case queryResultType
        case asOf = "asOf"
        case workItems
    }
}
