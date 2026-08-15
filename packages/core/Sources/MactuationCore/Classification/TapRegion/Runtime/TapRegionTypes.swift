import Foundation

public enum TapRegionSide: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right

    public var opposite: TapRegionSide {
        self == .left ? .right : .left
    }
}

public enum TapRegionPrediction: String, Codable, Equatable, Sendable {
    case left
    case right
    case unknown

    public init(side: TapRegionSide) {
        self = side == .left ? .left : .right
    }

    public var side: TapRegionSide? {
        switch self {
        case .left: return .left
        case .right: return .right
        case .unknown: return nil
        }
    }
}

public enum TapRegionPattern: String, Codable, CaseIterable, Hashable, Sendable {
    case double
    case triple

    public var memberCount: Int {
        switch self {
        case .double: return 2
        case .triple: return 3
        }
    }
}

public enum TapRegionAggregationStrategy: String, Codable, Sendable {
    case medianMembers
}
