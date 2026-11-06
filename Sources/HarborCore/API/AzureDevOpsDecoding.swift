import Foundation

enum AzureDevOpsDecoding {
    static func decode<T: Decodable>(_: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Azure DevOps uses ISO 8601 format with microseconds and timezone
            // Example: "2024-01-15T10:30:45.123456Z" or "2024-01-15T10:30:45.123Z"
            let formatters = [
                ISO8601DateFormatter.azureDevOpsFractional,
                ISO8601DateFormatter.azureDevOpsStandard
            ]

            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

// Configured once, then only read: ISO8601DateFormatter is thread-safe for that.
// Scoped `nonisolated(unsafe)` instead of a retroactive Sendable conformance on
// Foundation's type, which would change it for every module.
extension ISO8601DateFormatter {
    /// Any number of fractional digits (Azure sends up to 7).
    nonisolated(unsafe) static let azureDevOpsFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let azureDevOpsStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
