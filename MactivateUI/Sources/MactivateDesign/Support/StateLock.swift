import Foundation

/// Mutable state behind a lock, exposed only through a synchronous closure.
///
/// Wrapping the lock this way keeps `NSLock`'s `noasync` methods out of async
/// functions — the compiler is right that taking a lock across a suspension point
/// is a bug, and this shape makes it impossible to do by accident.
final class StateLock<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    var current: Value {
        withLock { $0 }
    }
}
