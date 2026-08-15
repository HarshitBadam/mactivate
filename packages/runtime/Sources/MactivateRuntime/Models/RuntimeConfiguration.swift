import Foundation

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var spatialTapBindings: SpatialTapBindings
    public var spatialTapDispatchEnabled: Bool
    public var panelHintsEnabled: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        spatialTapBindings: SpatialTapBindings = SpatialTapBindings(),
        spatialTapDispatchEnabled: Bool = true,
        panelHintsEnabled: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.spatialTapBindings = spatialTapBindings
        self.spatialTapDispatchEnabled = spatialTapDispatchEnabled
        self.panelHintsEnabled = panelHintsEnabled
    }

    public static let `default` = RuntimeConfiguration()

    public static let failClosed = RuntimeConfiguration(
        spatialTapBindings: SpatialTapBindings(),
        spatialTapDispatchEnabled: false,
        panelHintsEnabled: false
    )

    var isCurrentAndValid: Bool {
        schemaVersion == Self.currentSchemaVersion && spatialTapBindings.isValid
    }
}
