import AppKit
import SwiftUI

struct DiagnosticsPane: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            SettingsPageHeader(
                title: "Diagnostics",
                subtitle: "Review the latest tap decision and runtime report.",
                symbol: "waveform.path.ecg"
            )
            if let feedback = state.lastTapFeedback {
                SettingsCard(
                    "Latest tap decision",
                    subtitle: "Updates after every detected impact group.",
                    symbol: "waveform"
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: SettingsMetrics.controlGap
                    ) {
                        Text(state.tapFeedbackSummary)
                            .font(.headline)
                        if case .rejected = feedback.outcome {
                            Label(
                                state.tapFeedbackSummaryDetail,
                                systemImage: "lightbulb"
                            )
                            .font(.callout)
                            .foregroundStyle(.orange)
                        } else {
                            Text(state.tapFeedbackSummaryDetail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: SettingsMetrics.fieldGap) {
                            Text("Peak \(feedback.features.peakG, format: .number.precision(.fractionLength(3))) g")
                            Text("\(feedback.memberCount) detected impact\(feedback.memberCount == 1 ? "" : "s")")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ScrollView {
                Text(state.diagnosticText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SettingsMetrics.cardInset)
            }
            .scrollIndicators(.hidden)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
            )
            HStack {
                Button("Copy Diagnostics", action: copyDiagnostics)
                Spacer()
                if let warning = state.recentWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, SettingsMetrics.pageInset)
        .padding(.top, SettingsMetrics.paneTopInset)
        .padding(.bottom, SettingsMetrics.pageInset)
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            state.diagnosticText,
            forType: .string
        )
    }
}
