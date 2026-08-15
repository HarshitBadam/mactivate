import Darwin
import Foundation

struct DisplayServicesStatus {
    let frameworkPresent: Bool
    let frameworkLoadable: Bool
    let detail: String
}

enum DisplayServicesProbe {
    static let frameworkDirectory =
        "/System/Library/PrivateFrameworks/DisplayServices.framework"
    private static let frameworkBinary =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    static func inspect() -> DisplayServicesStatus {
        let present = FileManager.default.fileExists(atPath: frameworkDirectory)
        guard present else {
            return DisplayServicesStatus(
                frameworkPresent: false,
                frameworkLoadable: false,
                detail: "framework absent"
            )
        }

        guard let handle = dlopen(frameworkBinary, RTLD_LAZY | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown dlopen failure"
            return DisplayServicesStatus(
                frameworkPresent: true,
                frameworkLoadable: false,
                detail: "framework present but could not load: \(reason)"
            )
        }
        dlclose(handle)

        // Prior art names an Objective-C client and key, but does not establish a
        // stable constructor/method ABI. Loading the framework is safe; inventing
        // a call signature is not.
        return DisplayServicesStatus(
            frameworkPresent: true,
            frameworkLoadable: true,
            detail: "framework present; read method unverified"
        )
    }
}
