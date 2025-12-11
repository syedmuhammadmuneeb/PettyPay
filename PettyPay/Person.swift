import Foundation
import SwiftUI

struct Person: Identifiable, Hashable {
    let id: UUID
    var name: String
    // Optional accent color for avatar display
    var color: Color

    init(id: UUID = UUID(), name: String, color: Color = .blue) {
        self.id = id
        self.name = name
        self.color = color
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        let raw = (first + last)
        return raw.isEmpty ? String(name.prefix(1)) : raw
    }
}
