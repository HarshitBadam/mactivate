import CoreFoundation
import Foundation
import IOKit
import IOKit.hid
import MactuationCore

final class IMUChannel {
    weak var owner: SPUIMUSource?
    let path: SensorPath
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let reportBufferLength: Int

    init(owner: SPUIMUSource, path: SensorPath, device: IOHIDDevice,
         reportBufferLength: Int) {
        self.owner = owner
        self.path = path
        self.device = device
        self.reportBufferLength = reportBufferLength
        reportBuffer = .allocate(capacity: reportBufferLength)
        reportBuffer.initialize(repeating: 0, count: reportBufferLength)
    }

    deinit {
        reportBuffer.deinitialize(count: reportBufferLength)
        reportBuffer.deallocate()
    }
}

final class StartHandshake {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedResult: Result<Void, Error>?
    private var cancelled = false

    @discardableResult
    func complete(_ result: Result<Void, Error>) -> Bool {
        let accepted = lock.withLock {
            guard !cancelled else { return false }
            storedResult = result
            return true
        }
        if accepted { semaphore.signal() }
        return accepted
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    var result: Result<Void, Error>? {
        lock.withLock { storedResult }
    }
}

final class ResultBox<Value> {
    var result: Result<Value, Error>?
}

func imuInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let channel = Unmanaged<IMUChannel>.fromOpaque(context).takeUnretainedValue()
    channel.owner?.receive(
        channel: channel,
        result: result,
        report: report,
        length: Int(reportLength)
    )
}
