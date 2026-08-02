import Foundation

/// One step of a calibration run, as reported by the engine.
public enum CalibrationProgress: Equatable, Sendable {
    /// Waiting for the user to be ready; the UI shows the instruction.
    case waiting(instruction: String)
    /// Recording the at-rest noise floor before asking for input. Users read
    /// this as "hold still", so it is a named step rather than hidden latency.
    case measuringBaseline(secondsRemaining: Double)
    /// Collecting repetitions.
    case collecting(captured: Int, target: Int)
    /// A repetition was captured — used for the per-repetition tick feedback.
    case captured(index: Int, confidence: Double)
    /// Something fired that the user did not intend. Counted and shown, because
    /// a calibration that hides its false fires is how a bad threshold ships.
    case falseFire(count: Int)
    case finished(result: CalibrationResult)
    case failed(reason: String)
}

/// The measured outcome of a calibration run. Calibration always ends with these
/// numbers on screen; "Done" alone is not an acceptable ending.
public struct CalibrationResult: Equatable, Sendable {
    public var detected: Int
    public var attempted: Int
    public var falseFires: Int
    public var measuredAt: Date
    /// Free-form notes from the engine, e.g. "lateral separation weak".
    public var note: String?

    public init(detected: Int, attempted: Int, falseFires: Int, measuredAt: Date = Date(), note: String? = nil) {
        self.detected = detected
        self.attempted = attempted
        self.falseFires = falseFires
        self.measuredAt = measuredAt
        self.note = note
    }

    public var recall: Double {
        attempted == 0 ? 0 : Double(detected) / Double(attempted)
    }

    /// The project's qualification floor: ≥95% recall with no unintended fires.
    /// The UI states the bar rather than just passing or failing silently.
    public var meetsQualificationBar: Bool {
        recall >= 0.95 && falseFires == 0
    }

    /// "Detected 9 of 10 taps, 0 false fires" — the exact read-out the UX rules
    /// ask for.
    public var readout: String {
        let fires = falseFires == 1 ? "1 false fire" : "\(falseFires) false fires"
        return "Detected \(detected) of \(attempted) taps, \(fires)"
    }

    public var tone: Tone {
        if meetsQualificationBar { return .ready }
        if recall >= 0.7 && falseFires <= 1 { return .attention }
        return .failure
    }

    /// What to tell the user to do next, in plain language.
    public var recommendation: String {
        if meetsQualificationBar {
            return "This region is ready to use."
        }
        if falseFires > 0 {
            return "Something fired without you tapping. Try a firmer, more deliberate tap in one spot, or lower this region's sensitivity."
        }
        if recall >= 0.7 {
            return "Most taps registered. Calibrate again in the position you actually sit in, and tap the same spot each time."
        }
        return "Too few taps registered to trust this region. Bindings here will often do nothing until calibration improves."
    }

    public func regionCalibrationState() -> RegionCalibrationState {
        meetsQualificationBar
            ? .calibrated(recall: recall, falseFires: falseFires, calibratedAt: measuredAt)
            : .lowConfidence(recall: recall, falseFires: falseFires, calibratedAt: measuredAt)
    }
}

/// UI-side state machine driving a calibration screen.
///
/// It is a value type with an explicit `apply` so the flow is unit-testable
/// without a view, and so the screen has exactly one source of truth for "what
/// should be on screen right now".
public struct CalibrationSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case instructing(String)
        case baseline(secondsRemaining: Double)
        case collecting(captured: Int, target: Int, falseFires: Int)
        case summary(CalibrationResult)
        case failed(String)
    }

    public enum Subject: Equatable, Sendable {
        case tap(region: TapRegionID, count: TapCount)
        case handNear
    }

    public var subject: Subject
    public private(set) var phase: Phase = .idle
    /// Ticks appended per captured repetition, used for the dot strip that fills
    /// in as the user taps.
    public private(set) var capturedConfidences: [Double] = []

    public init(subject: Subject) {
        self.subject = subject
    }

    public mutating func apply(_ progress: CalibrationProgress) {
        switch progress {
        case .waiting(let instruction):
            phase = .instructing(instruction)
        case .measuringBaseline(let remaining):
            phase = .baseline(secondsRemaining: remaining)
        case .collecting(let captured, let target):
            phase = .collecting(captured: captured, target: target, falseFires: falseFireCount)
        case .captured(let index, let confidence):
            capturedConfidences.append(confidence)
            if case .collecting(_, let target, let falseFires) = phase {
                phase = .collecting(captured: index, target: target, falseFires: falseFires)
            }
        case .falseFire(let count):
            falseFireCount = count
            if case .collecting(let captured, let target, _) = phase {
                phase = .collecting(captured: captured, target: target, falseFires: count)
            }
        case .finished(let result):
            phase = .summary(result)
        case .failed(let reason):
            phase = .failed(reason)
        }
    }

    private var falseFireCount = 0

    public mutating func reset() {
        phase = .idle
        capturedConfidences = []
        falseFireCount = 0
    }

    public var isRunning: Bool {
        switch phase {
        case .instructing, .baseline, .collecting: return true
        case .idle, .summary, .failed: return false
        }
    }

    /// Fraction complete, for a determinate progress view. `nil` during phases
    /// with no meaningful fraction, which then use an indeterminate indicator
    /// rather than a fake one.
    public var progressFraction: Double? {
        switch phase {
        case .collecting(let captured, let target, _):
            return target == 0 ? nil : min(1, Double(captured) / Double(target))
        case .summary:
            return 1
        default:
            return nil
        }
    }

    /// The instruction line. Written imperatively and in the user's terms: tap
    /// where you will actually tap, at the strength you will actually use.
    public var instruction: String {
        switch phase {
        case .idle:
            switch subject {
            case .tap(_, let count):
                return "You will be asked to \(count.displayName.lowercased()) ten times, in the exact spot you would normally use."
            case .handNear:
                return "You will be asked to wave over the notch a few times, from where you normally sit."
            }
        case .instructing(let text):
            return text
        case .baseline:
            return "Hold still. Measuring how quiet your Mac is right now."
        case .collecting(let captured, let target, _):
            switch subject {
            case .tap(_, let count):
                return "\(count.displayName) — \(captured) of \(target)"
            case .handNear:
                return "Wave over the notch — \(captured) of \(target)"
            }
        case .summary(let result):
            return result.readout
        case .failed(let reason):
            return reason
        }
    }
}
