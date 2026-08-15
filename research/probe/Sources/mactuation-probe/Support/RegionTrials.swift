import Foundation
import MactuationCore
import MactuationResearch

struct RegionCaptureTrial {
    var side: TapRegionProbeSide
    var intensity: TapRegionProbeIntensity
    var repetition: Int
}

struct RegionMultiTapTrial {
    var side: TapRegionProbeSide
    var pattern: TapRegionMultiTapPattern
    var repetition: Int
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}

func regionTrials(count: Int, seed: UInt64) -> [RegionCaptureTrial] {
    var trials: [RegionCaptureTrial] = []
    for repetition in 1...count {
        for intensity in TapRegionProbeIntensity.allCases {
            for side in TapRegionProbeSide.allCases {
                trials.append(RegionCaptureTrial(
                    side: side,
                    intensity: intensity,
                    repetition: repetition
                ))
            }
        }
    }
    var generator = SeededGenerator(seed: seed)
    trials.shuffle(using: &generator)
    return trials
}

func regionMultiTapTrials(
    count: Int,
    seed: UInt64
) -> [RegionMultiTapTrial] {
    var trials: [RegionMultiTapTrial] = []
    for repetition in 1...count {
        for pattern in TapRegionMultiTapPattern.allCases {
            for side in TapRegionProbeSide.allCases {
                trials.append(RegionMultiTapTrial(
                    side: side,
                    pattern: pattern,
                    repetition: repetition
                ))
            }
        }
    }
    var generator = SeededGenerator(seed: seed)
    trials.shuffle(using: &generator)
    return trials
}
