import Foundation
import MactuationCapture
import MactuationCore

extension TapClassifier {
    /// Canonical, locale-independent line encoding of one classified group —
    /// the byte-identical replay contract is defined over these lines.
    public static func canonicalLine(for group: TapGroup) -> String {
        let verdict: String
        switch group.verdict {
        case .acceptedComfort: verdict = "accept:comfort"
        case .acceptedFirm(let side): verdict = "accept:firm:\(side.rawValue)"
        case .rejected: verdict = "reject"
        }
        let members = group.members.map { member in
            ["t=" + CaptureFormat.encode(member.time),
             "peak=" + CaptureFormat.encode(member.peakG),
             "z25=" + CaptureFormat.encode(member.zImpulseMgS),
             "lat25=" + CaptureFormat.encode(member.lateralImpulseMgS),
             "decay=" + CaptureFormat.encode(member.decayMs)].joined(separator: ",")
        }.joined(separator: ";")
        return "\(verdict)|n=\(group.members.count)|\(members)"
    }

    /// Order-sensitive digest of a classification run, including the
    /// calibration version so a config change can never alias an old digest.
    public func digest(of groups: [TapGroup]) -> String {
        var digest = StreamDigest()
        digest.update(string: calibration.version)
        for group in groups {
            digest.update(string: Self.canonicalLine(for: group))
        }
        return digest.value
    }
}
