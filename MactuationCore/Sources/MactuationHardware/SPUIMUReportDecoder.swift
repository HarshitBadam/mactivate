import Foundation

struct DecodedIMUReport: Equatable {
    let x: Double
    let y: Double
    let z: Double
}

enum SPUIMUReportDecoder {
    static let minimumLength = 18

    static func decode(_ bytes: UnsafeBufferPointer<UInt8>) -> DecodedIMUReport? {
        guard bytes.count >= minimumLength else { return nil }
        return DecodedIMUReport(
            x: Double(decodeInt32(bytes, at: 6)) / 65_536,
            y: Double(decodeInt32(bytes, at: 10)) / 65_536,
            z: Double(decodeInt32(bytes, at: 14)) / 65_536
        )
    }

    static func decode(_ data: Data) -> DecodedIMUReport? {
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return decode(bytes)
        }
    }

    private static func decodeInt32(_ bytes: UnsafeBufferPointer<UInt8>,
                                    at offset: Int) -> Int32 {
        let value = UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
        return Int32(bitPattern: value)
    }
}
