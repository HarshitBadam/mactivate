import Foundation
import MactuationCore
import MactuationResearch

func printRegionMetrics(
    _ title: String,
    metrics: TapRegionQualificationMetrics
) {
    print("\(title):")
    print(String(
        format: "  precision: left %.1f%%  right %.1f%%",
        metrics.leftPrecision * 100,
        metrics.rightPrecision * 100
    ))
    for key in metrics.groupCoverage.keys.sorted() {
        print(String(
            format: "  correct coverage %@: %.1f%%",
            key,
            metrics.groupCoverage[key, default: 0] * 100
        ))
    }
    print(String(
        format: "  classified: %.1f%%  wrong: %d  ambiguous: %d",
        metrics.classifiedFraction * 100,
        metrics.incorrect,
        metrics.ambiguous
    ))
}

func printRegionFit(
    _ fit: TapRegionThresholdFit,
    validation: [TapRegionProbeObservation]? = nil
) {
    let model = fit.model
    print("Frozen scalar model:")
    print("  feature: \(model.featureName)")
    print(String(
        format: "  %@ below %.8f, ambiguous through %.8f, %@ above",
        model.lowerSide.rawValue,
        model.lowerBoundary,
        model.upperBoundary,
        model.lowerSide == .left ? "right" : "left"
    ))
    printRegionMetrics("Training (feature selection)", metrics: fit.metrics)
    guard let validation else {
        print("Result: exploratory only — collect an independent validation session.")
        return
    }
    let metrics = TapRegionProbeAnalyzer.evaluate(
        model,
        observations: validation
    )
    printRegionMetrics("Independent validation", metrics: metrics)
    print(metrics.qualifies
        ? "Result: PASS — meets 95% precision and 90% per-group coverage gates."
        : "Result: FAIL — do not expose left/right zones with this model.")
}

func printRegionScreening(
    _ observations: [TapRegionProbeObservation]
) throws {
    let ranked = try TapRegionProbeAnalyzer.rankedFits(observations)
    print("Top scalar feature screens:")
    for fit in ranked.prefix(5) {
        print(String(
            format: "  %@ — precision L %.1f%% R %.1f%%, minimum coverage %.1f%%, wrong %d",
            fit.model.featureName,
            fit.metrics.leftPrecision * 100,
            fit.metrics.rightPrecision * 100,
            fit.metrics.minimumGroupCoverage * 100,
            fit.metrics.incorrect
        ))
    }
    let foldCount = min(
        5,
        Set(observations.map(\.repetition)).count
    )
    guard foldCount >= 2 else {
        print("Held-out screening skipped: at least two repetitions are required.")
        return
    }
    let crossValidation = try TapRegionProbeAnalyzer.crossValidate(
        observations,
        folds: foldCount
    )
    let selectedFeatures = Dictionary(
        grouping: crossValidation.foldModels,
        by: \.featureName
    ).mapValues(\.count)
    printRegionMetrics(
        "\(foldCount)-fold held-out screening",
        metrics: crossValidation.metrics
    )
    print(
        "  selected features by fold: " +
            selectedFeatures.keys.sorted().map {
                "\($0)=\(selectedFeatures[$0, default: 0])"
            }.joined(separator: ", ")
    )

    let linearFits = try TapRegionLinearProbeAnalyzer.rankedFits(observations)
    print("Top regularized linear feature sets:")
    for fit in linearFits.prefix(5) {
        print(String(
            format: "  %@ — precision L %.1f%% R %.1f%%, minimum coverage %.1f%%, wrong %d",
            fit.model.name,
            fit.metrics.leftPrecision * 100,
            fit.metrics.rightPrecision * 100,
            fit.metrics.minimumGroupCoverage * 100,
            fit.metrics.incorrect
        ))
    }
    let linearCrossValidation = try TapRegionLinearProbeAnalyzer.crossValidate(
        observations,
        folds: foldCount
    )
    let selectedLinearModels = Dictionary(
        grouping: linearCrossValidation.foldModels,
        by: \.name
    ).mapValues(\.count)
    printRegionMetrics(
        "\(foldCount)-fold held-out linear screening",
        metrics: linearCrossValidation.metrics
    )
    print(
        "  selected models by fold: " +
            selectedLinearModels.keys.sorted().map {
                "\($0)=\(selectedLinearModels[$0, default: 0])"
            }.joined(separator: ", ")
    )
}

func printRegionTransferCandidates(
    training: [TapRegionProbeObservation],
    validation: [TapRegionProbeObservation]
) throws {
    let transferred = try TapRegionProbeAnalyzer.rankedFits(training).map {
        (
            fit: $0,
            validation: TapRegionProbeAnalyzer.evaluate(
                $0.model,
                observations: validation
            )
        )
    }.sorted {
        let lhs = [
            $0.validation.qualifies ? 1.0 : 0,
            $0.validation.minimumGroupCoverage,
            min($0.validation.leftPrecision, $0.validation.rightPrecision),
            -Double($0.validation.incorrect)
        ]
        let rhs = [
            $1.validation.qualifies ? 1.0 : 0,
            $1.validation.minimumGroupCoverage,
            min($1.validation.leftPrecision, $1.validation.rightPrecision),
            -Double($1.validation.incorrect)
        ]
        if lhs != rhs {
            return !lhs.lexicographicallyPrecedes(rhs)
        }
        return $0.fit.model.featureName < $1.fit.model.featureName
    }

    print("Frozen pilot-feature transfer ranking:")
    for result in transferred.prefix(5) {
        print(String(
            format: "  %@ — validation precision L %.1f%% R %.1f%%, minimum coverage %.1f%%, wrong %d",
            result.fit.model.featureName,
            result.validation.leftPrecision * 100,
            result.validation.rightPrecision * 100,
            result.validation.minimumGroupCoverage * 100,
            result.validation.incorrect
        ))
    }
}

func printMultiTapMetrics(
    _ title: String,
    metrics: TapRegionQualificationMetrics
) {
    let displayNames = [
        "left-comfort": "left-double",
        "left-firm": "left-triple",
        "right-comfort": "right-double",
        "right-firm": "right-triple"
    ]
    print("\(title):")
    print(String(
        format: "    precision: left %.1f%%  right %.1f%%",
        metrics.leftPrecision * 100,
        metrics.rightPrecision * 100
    ))
    for key in metrics.groupCoverage.keys.sorted() {
        print(String(
            format: "    correct coverage %@: %.1f%%",
            displayNames[key] ?? key,
            metrics.groupCoverage[key, default: 0] * 100
        ))
    }
    print(String(
        format: "    classified: %.1f%%  wrong: %d  ambiguous: %d",
        metrics.classifiedFraction * 100,
        metrics.incorrect,
        metrics.ambiguous
    ))
}

func printMultiTapScreening(
    _ gestures: [TapRegionMultiTapGesture]
) throws {
    print(
        "Multi-tap observations: \(gestures.count) gestures, " +
            "\(gestures.reduce(0) { $0 + $1.members.count }) detected impacts"
    )
    for result in try TapRegionMultiTapProbeAnalyzer.screen(gestures) {
        print("Strategy: \(result.name)")
        printMultiTapMetrics(
            "  Training",
            metrics: result.trainingMetrics
        )
        printMultiTapMetrics(
            "  Held-out",
            metrics: result.crossValidationMetrics
        )
        print(
            "    selected features: " +
                result.selectedFeatures.keys.sorted().map {
                    "\($0)=\(result.selectedFeatures[$0, default: 0])"
                }.joined(separator: ", ")
        )
    }
}
