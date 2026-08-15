import Foundation
import MactuationCapture
import MactuationCore
import MactuationResearch

func runRegionAnalysis(_ arguments: Arguments) throws {
    guard let trainingPath = try arguments.value(after: "--training") else {
        throw ProbeError.usage(
            "region-analyze requires --training <capture-directory>"
        )
    }
    let trainingReader = try CaptureReader(
        directory: URL(fileURLWithPath: trainingPath).standardizedFileURL
    )
    var training = try TapRegionProbeAnalyzer.observations(from: trainingReader)
    if let additionalPath = try arguments.value(after: "--training-additional") {
        let additionalReader = try CaptureReader(
            directory: URL(fileURLWithPath: additionalPath).standardizedFileURL
        )
        training += try TapRegionProbeAnalyzer.observations(
            from: additionalReader
        )
    }
    let fit = try TapRegionProbeAnalyzer.fit(training)
    try printRegionScreening(training)

    if let validationPath = try arguments.value(after: "--validation") {
        let validationReader = try CaptureReader(
            directory: URL(fileURLWithPath: validationPath).standardizedFileURL
        )
        let validation = try TapRegionProbeAnalyzer.observations(
            from: validationReader
        )
        try printRegionTransferCandidates(
            training: training,
            validation: validation
        )
        printRegionFit(fit, validation: validation)
    } else {
        printRegionFit(fit)
    }
}
