import Foundation

public enum JSONOutput {
    public static func encode<T: Encodable>(_ value: T, prettyPrinted: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONOutputError.invalidUTF8
        }
        return string
    }
}

public enum JSONOutputError: Error {
    case invalidUTF8
}
