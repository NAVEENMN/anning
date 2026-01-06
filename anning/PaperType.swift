import Foundation

enum PaperType: String, CaseIterable, Identifiable {
    case surveyPaper = "survey paper"
    case empiricalWork = "empirical work"
    case theoreticalProof = "theoretical proof"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .surveyPaper: return "Survey paper"
        case .empiricalWork: return "Empirical work"
        case .theoreticalProof: return "Theoretical proof"
        }
    }
}

func paperTypeFromStored(_ s: String?) -> PaperType {
    PaperType(rawValue: (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? .empiricalWork
}

