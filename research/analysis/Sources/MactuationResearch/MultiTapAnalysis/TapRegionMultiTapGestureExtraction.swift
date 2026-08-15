import Foundation
import MactuationCapture
import MactuationCore

extension TapRegionMultiTapProbeAnalyzer {
    private struct GestureKey: Hashable {
        var side: TapRegionProbeSide
        var pattern: TapRegionMultiTapPattern
        var repetition: Int
    }

    private struct IndexedMember {
        var index: Int
        var observation: TapRegionProbeObservation
    }

    public static func gestures(
        from reader: CaptureReader
    ) throws -> [TapRegionMultiTapGesture] {
        let labels = try reader.labels().filter {
            $0.notes.hasPrefix("auto-detected multi-tap")
        }
        guard !labels.isEmpty else {
            throw TapRegionMultiTapAnalysisError.missingLabels
        }
        let allLabels = try reader.labels().filter {
            $0.label.hasPrefix("palm-")
        }
        let allObservations = try TapRegionProbeAnalyzer.observations(
            from: reader
        )
        guard allLabels.count == allObservations.count else {
            throw TapRegionMultiTapAnalysisError.malformedLabel(
                "label/observation count mismatch"
            )
        }

        var grouped: [GestureKey: [IndexedMember]] = [:]
        for (label, observation) in zip(allLabels, allObservations)
        where label.notes.hasPrefix("auto-detected multi-tap") {
            guard let patternValue = noteValue("pattern", in: label.notes),
                  let pattern = TapRegionMultiTapPattern(
                    rawValue: patternValue
                  ),
                  let memberValue = noteValue("member", in: label.notes),
                  let memberIndex = memberValue.split(separator: "/")
                    .first.flatMap({ Int($0) }) else {
                throw TapRegionMultiTapAnalysisError.malformedLabel(label.notes)
            }
            let key = GestureKey(
                side: observation.side,
                pattern: pattern,
                repetition: observation.repetition
            )
            grouped[key, default: []].append(IndexedMember(
                index: memberIndex,
                observation: observation
            ))
        }

        return try grouped.map { key, indexedMembers in
            let sorted = indexedMembers.sorted { $0.index < $1.index }
            guard sorted.count == key.pattern.memberCount else {
                throw TapRegionMultiTapAnalysisError.incompleteGesture(
                    side: key.side,
                    pattern: key.pattern,
                    repetition: key.repetition,
                    expected: key.pattern.memberCount,
                    actual: sorted.count
                )
            }
            return TapRegionMultiTapGesture(
                side: key.side,
                pattern: key.pattern,
                repetition: key.repetition,
                members: sorted.map(\.observation)
            )
        }.sorted {
            ($0.members.first?.peakTimestamp ?? 0) <
                ($1.members.first?.peakTimestamp ?? 0)
        }
    }

    private static func noteValue(
        _ key: String,
        in notes: String
    ) -> String? {
        notes.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.first {
            $0.hasPrefix("\(key)=")
        }.map {
            String($0.dropFirst(key.count + 1))
        }
    }
}
