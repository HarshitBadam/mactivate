import Foundation
import MactuationCapture
import MactuationCore
import MactuationResearch

func runRegionMultiTapAnalysis(_ arguments: Arguments) throws {
    guard let trainingPath = try arguments.value(after: "--training") else {
        throw ProbeError.usage(
            "region-multitap-analyze requires --training <capture-directory>"
        )
    }
    let training = try TapRegionMultiTapProbeAnalyzer.gestures(
        from: CaptureReader(
            directory: URL(fileURLWithPath: trainingPath).standardizedFileURL
        )
    )
    let fitted = try TapRegionMultiTapProbeAnalyzer.fitStrategies(training)
    let validation: [TapRegionMultiTapGesture]?
    if let validationPath = try arguments.value(after: "--validation") {
        validation = try TapRegionMultiTapProbeAnalyzer.gestures(
            from: CaptureReader(
                directory: URL(
                    fileURLWithPath: validationPath
                ).standardizedFileURL
            )
        )
    } else {
        validation = nil
    }

    for strategy in fitted {
        print("Frozen strategy: \(strategy.strategy.name)")
        print("  feature: \(strategy.model.featureName)")
        printMultiTapMetrics(
            "  Training",
            metrics: strategy.trainingMetrics
        )
        if let validation {
            let metrics = TapRegionMultiTapProbeAnalyzer.evaluate(
                strategy,
                gestures: validation
            )
            printMultiTapMetrics("  Independent validation", metrics: metrics)
            print(metrics.qualifies
                ? "  Result: PASS"
                : "  Result: FAIL")
        }
    }
}
