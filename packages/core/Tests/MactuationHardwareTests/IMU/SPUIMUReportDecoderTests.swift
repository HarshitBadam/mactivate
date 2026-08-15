import Foundation
@testable import MactuationHardware
import XCTest

final class SPUIMUReportDecoderTests: XCTestCase {
    func testDecodesObservedOffsetsFromMinimumLengthReport() {
        var bytes = Data(repeating: 0, count: 18)
        write(Int32(65_536), to: &bytes, at: 6)
        write(Int32(-32_768), to: &bytes, at: 10)
        write(Int32(131_072), to: &bytes, at: 14)

        XCTAssertEqual(
            SPUIMUReportDecoder.decode(bytes),
            DecodedIMUReport(x: 1, y: -0.5, z: 2)
        )
    }

    func testAcceptsLongerObservedReport() {
        var bytes = Data(repeating: 0xAA, count: 22)
        write(Int32.min, to: &bytes, at: 6)
        write(Int32.max, to: &bytes, at: 10)
        write(0, to: &bytes, at: 14)

        let decoded = SPUIMUReportDecoder.decode(bytes)

        XCTAssertEqual(decoded?.x, -32_768)
        XCTAssertEqual(decoded?.y, Double(Int32.max) / 65_536)
        XCTAssertEqual(decoded?.z, 0)
    }

    func testRejectsShortReport() {
        XCTAssertNil(SPUIMUReportDecoder.decode(Data(repeating: 0, count: 17)))
    }

    private func write(_ value: Int32, to data: inout Data, at offset: Int) {
        let bits = UInt32(bitPattern: value)
        for index in 0..<4 {
            data[offset + index] = UInt8(truncatingIfNeeded: bits >> UInt32(index * 8))
        }
    }
}
