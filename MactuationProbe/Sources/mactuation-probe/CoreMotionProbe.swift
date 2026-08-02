import CoreMotion
import Foundation

enum CoreMotionProbe {
    static func accelerometerAvailable() -> Bool? {
        // The macOS SDK marks CMMotionManager unavailable at compile time even
        // though the Objective-C class can exist at runtime. Resolve it
        // dynamically so this probe records the machine's empirical answer.
        guard let managerType = NSClassFromString("CMMotionManager") as? NSObject.Type else {
            return nil
        }
        let manager = managerType.init()
        return manager.value(forKey: "accelerometerAvailable") as? Bool
    }
}
