import Foundation

public enum JSONOutput {
    public static func encode<T: Encodable>(_ value: T, prettyPrinted: Bool = true) throws -> String {
        let data = try encodeData(value, prettyPrinted: prettyPrinted)
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONOutputError.invalidUTF8
        }
        return string
    }

    public static func encodeData<T: Encodable>(_ value: T, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(value)
    }
}

public enum JSONOutputError: Error {
    case invalidUTF8
}
