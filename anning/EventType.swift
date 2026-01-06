import Foundation

enum EventType: String, CaseIterable, Identifiable {
    case supporting
    case unsupporting
    case landmark
    case informative
    case improvement

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .supporting: return "checkmark.circle"
        case .unsupporting: return "xmark.circle"
        case .landmark: return "flag.checkered"
        case .informative: return "info.circle"
        case .improvement: return "arrow.up.circle"
        }
    }
}

func eventTypeFromStored(_ s: String?) -> EventType {
    EventType(rawValue: (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? .informative
}

