import Foundation

/// The physical surface a tap lands on. Only these two are in product scope.
public enum TapSurface: String, Codable, CaseIterable, Sendable {
    case palmRest
    case desk

    public var displayName: String {
        switch self {
        case .palmRest: return "Palm Rest"
        case .desk: return "Desk"
        }
    }
}

/// Lateral placement within a surface. Region localization is a hypothesis
/// (H-TAP-REGION), so the UI must be able to present a machine where only
/// `whole` survived calibration.
public enum TapZone: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right
    /// The surface could not be localized, so it is one region.
    case whole

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        case .whole: return "Whole"
        }
    }
}

public struct TapRegionID: Hashable, Codable, Sendable, CustomStringConvertible, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(surface: TapSurface, zone: TapZone) {
        self.rawValue = "\(surface.rawValue).\(zone.rawValue)"
    }

    public var description: String { rawValue }
}

/// A normalized rectangle in the device-map coordinate space, where (0,0) is the
/// top-left of the drawn MacBook-plus-desk illustration and (1,1) its
/// bottom-right. Keeping the geometry in the model means the map, the notch
/// panel, and the calibration screen all place regions identically.
public struct NormalizedRect: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// How well a region is calibrated, which is what decides whether the UI offers
/// its bindings, warns about them, or hides them.
public enum RegionCalibrationState: Equatable, Codable, Sendable {
    /// Never calibrated. Bindings are editable but inert, and the UI says so.
    case uncalibrated
    /// Calibrated with a measured result.
    case calibrated(recall: Double, falseFires: Int, calibratedAt: Date)
    /// Calibrated, but below the qualification bar; bindings stay but are marked
    /// low confidence and the classifier is expected to fail closed often.
    case lowConfidence(recall: Double, falseFires: Int, calibratedAt: Date)
    /// The sensor path this region needs is not available on this machine.
    case unsupported(reason: String)

    public var allowsBindings: Bool {
        switch self {
        case .calibrated, .lowConfidence, .uncalibrated: return true
        case .unsupported: return false
        }
    }

    public var tone: Tone {
        switch self {
        case .uncalibrated: return .attention
        case .calibrated: return .ready
        case .lowConfidence: return .attention
        case .unsupported: return .unavailable
        }
    }
}

/// One calibrated tap region: a surface, a zone, where to draw it, and its
/// calibration state.
public struct TapRegion: Identifiable, Equatable, Codable, Sendable {
    public var id: TapRegionID
    public var surface: TapSurface
    public var zone: TapZone
    /// User-visible name. Defaults to "Left Palm Rest" and friends, renameable
    /// because a desk region's meaning is personal ("Coffee side").
    public var name: String
    public var frame: NormalizedRect
    public var calibration: RegionCalibrationState

    public init(
        surface: TapSurface,
        zone: TapZone,
        name: String? = nil,
        frame: NormalizedRect,
        calibration: RegionCalibrationState = .uncalibrated
    ) {
        self.id = TapRegionID(surface: surface, zone: zone)
        self.surface = surface
        self.zone = zone
        self.name = name ?? TapRegion.defaultName(surface: surface, zone: zone)
        self.frame = frame
        self.calibration = calibration
    }

    public static func defaultName(surface: TapSurface, zone: TapZone) -> String {
        switch (surface, zone) {
        case (.palmRest, .whole): return "Palm Rest"
        case (.desk, .whole): return "Desk"
        case (.desk, .center): return "Desk, In Front"
        default: return "\(zone.displayName) \(surface.displayName)"
        }
    }

    /// The accessibility label spoken for the region on the device map.
    public var accessibilityLabel: String {
        "\(name), \(surface.displayName)"
    }
}
