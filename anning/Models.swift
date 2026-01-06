import Foundation

struct AuthorInput: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var firstName: String
    var lastName: String
}

