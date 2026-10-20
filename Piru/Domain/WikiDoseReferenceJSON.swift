import Foundation

/// Source metadata is intentionally open-ended. Keep its nulls, arrays and
/// nested qualifications instead of reducing an observation to a dose number.
nonisolated enum WikiDoseReferenceJSON: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([WikiDoseReferenceJSON])
    case object([String: WikiDoseReferenceJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Non-finite source number")
            }
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WikiDoseReferenceJSON].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: WikiDoseReferenceJSON].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    var objectValue: [String: WikiDoseReferenceJSON]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [WikiDoseReferenceJSON]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    subscript(key: String) -> WikiDoseReferenceJSON? { objectValue?[key] }

    /// Scalar source text. Views walk arrays and objects so their qualifications
    /// stay separate rather than presenting serialized JSON to a reader.
    var displayText: String {
        switch self {
        case .null: ""
        case let .bool(value): String(value)
        case let .number(value): String(value)
        case let .string(value): value
        case .array, .object: ""
        }
    }
}
