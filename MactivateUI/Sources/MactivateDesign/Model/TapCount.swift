import Foundation

/// The complete tap vocabulary. Cross-region sequences and rhythms are out of
/// scope, so this enum is deliberately closed at three.
public enum TapCount: Int, Codable, CaseIterable, Identifiable, Sendable {
    case single = 1
    case double = 2
    case triple = 3

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .single: return "Single Tap"
        case .double: return "Double Tap"
        case .triple: return "Triple Tap"
        }
    }

    /// Short form for tight rows, e.g. the notch panel's binding list.
    public var shortName: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        case .triple: return "Triple"
        }
    }

    /// SF Symbol showing the count as filled dots.
    public var symbolName: String {
        switch self {
        case .single: return "circle.fill"
        case .double: return "circle.grid.2x1.fill"
        case .triple: return "circle.grid.3x1.fill"
        }
    }
}
