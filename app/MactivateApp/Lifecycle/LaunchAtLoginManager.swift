import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var title: String {
        switch self {
        case .disabled:
            return "Off"
        case .enabled:
            return "On"
        case .requiresApproval:
            return "Approval required in System Settings"
        case .unavailable:
            return "Unavailable"
        }
    }

    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

protocol LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

final class LaunchAtLoginManager: LaunchAtLoginManaging {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
