import Foundation
import MactuationCore

public struct ActionIdentifier: RawRepresentable, Codable, Equatable, Hashable,
    Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var isValid: Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf8.count <= 256
    }
}

public enum TapPattern: Int, Codable, CaseIterable, Hashable, Sendable {
    case single = 1
    case double = 2
    case triple = 3
}

public struct TapBindings: Codable, Equatable, Sendable {
    public var single: ActionIdentifier?
    public var double: ActionIdentifier?
    public var triple: ActionIdentifier?

    public init(single: ActionIdentifier? = nil,
                double: ActionIdentifier? = nil,
                triple: ActionIdentifier? = nil) {
        self.single = single
        self.double = double
        self.triple = triple
    }

    public subscript(pattern: TapPattern) -> ActionIdentifier? {
        get {
            switch pattern {
            case .single: return single
            case .double: return double
            case .triple: return triple
            }
        }
        set {
            switch pattern {
            case .single: single = newValue
            case .double: double = newValue
            case .triple: triple = newValue
            }
        }
    }

    var isValid: Bool {
        [single, double, triple].compactMap { $0 }.allSatisfy(\.isValid)
    }
}

public struct PalmTapGesture: Codable, Equatable, Hashable, Sendable {
    public var side: TapRegionSide
    public var pattern: TapRegionPattern

    public init(side: TapRegionSide, pattern: TapRegionPattern) {
        self.side = side
        self.pattern = pattern
    }

    public static let leftDouble = PalmTapGesture(
        side: .left,
        pattern: .double
    )
    public static let leftTriple = PalmTapGesture(
        side: .left,
        pattern: .triple
    )
    public static let rightDouble = PalmTapGesture(
        side: .right,
        pattern: .double
    )
    public static let rightTriple = PalmTapGesture(
        side: .right,
        pattern: .triple
    )

    public static let allCases: [PalmTapGesture] = [
        .leftDouble,
        .leftTriple,
        .rightDouble,
        .rightTriple
    ]
}

public struct SpatialTapBindings: Codable, Equatable, Sendable {
    public var leftDouble: ActionIdentifier?
    public var leftTriple: ActionIdentifier?
    public var rightDouble: ActionIdentifier?
    public var rightTriple: ActionIdentifier?

    public init(
        leftDouble: ActionIdentifier? = nil,
        leftTriple: ActionIdentifier? = nil,
        rightDouble: ActionIdentifier? = nil,
        rightTriple: ActionIdentifier? = nil
    ) {
        self.leftDouble = leftDouble
        self.leftTriple = leftTriple
        self.rightDouble = rightDouble
        self.rightTriple = rightTriple
    }

    public subscript(gesture: PalmTapGesture) -> ActionIdentifier? {
        get {
            switch (gesture.side, gesture.pattern) {
            case (.left, .double): return leftDouble
            case (.left, .triple): return leftTriple
            case (.right, .double): return rightDouble
            case (.right, .triple): return rightTriple
            }
        }
        set {
            switch (gesture.side, gesture.pattern) {
            case (.left, .double): leftDouble = newValue
            case (.left, .triple): leftTriple = newValue
            case (.right, .double): rightDouble = newValue
            case (.right, .triple): rightTriple = newValue
            }
        }
    }

    public var isEmpty: Bool {
        PalmTapGesture.allCases.allSatisfy { self[$0] == nil }
    }

    var isValid: Bool {
        PalmTapGesture.allCases.compactMap { self[$0] }
            .allSatisfy(\.isValid)
    }
}
