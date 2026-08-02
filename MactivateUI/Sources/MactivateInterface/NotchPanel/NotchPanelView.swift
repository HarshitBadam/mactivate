#if os(macOS)
import SwiftUI
import MactivateDesign

/// The primary surface: the workspace that drops out of the notch when you wave.
///
/// Its job is not to be a settings window in a funny shape. It answers, in one
/// glance: what do my taps do right now, what can I press, and is any of this
/// actually working. Anything that needs a paragraph of explanation lives in the
/// main window instead, one click away at the bottom of the panel.
public struct NotchPanelView: View {
    @Bindable var model: AppModel
    let layout: NotchPanelLayout
    let openMainWindow: (MainWindowSection) -> Void

    @Environment(\.motionProfile) private var motion
    @State private var runningSlotID: UUID?

    public init(
        model: AppModel,
        layout: NotchPanelLayout,
        openMainWindow: @escaping (MainWindowSection) -> Void
    ) {
        self.model = model
        self.layout = layout
        self.openMainWindow = openMainWindow
    }

    public var body: some View {
        ZStack(alignment: .top) {
            NotchPanelBackground(layout: layout)

            VStack(spacing: 0) {
                // Clears the physical notch so no content hides behind the bezel.
                Spacer().frame(height: max(layout.notch.height, 10) + Metrics.Spacing.snug)

                header
                Divider().padding(.horizontal, Metrics.Spacing.roomy)

                content
                    .frame(maxHeight: .infinity, alignment: .top)

                footer
            }
            .padding(.bottom, Metrics.Spacing.regular)

            if let acknowledgement = model.acknowledgement {
                AcknowledgementBanner(entry: acknowledgement)
                    .padding(.top, layout.notch.height + Metrics.Spacing.roomy)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: layout.panel.width, height: layout.panel.height)
        .animation(motion.acknowledgementAnimation, value: model.acknowledgement?.id)
        .onHover { isInside in
            if isInside { model.panel.handle(.pointerEnteredPanel) }
        }
        .onKeyPress(.escape) {
            model.panel.handle(.dismissRequested)
            return .handled
        }
        .accessibilityLabel("Mactivate workspace")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Metrics.Spacing.regular) {
            HStack(spacing: Metrics.Spacing.snug) {
                Image(systemName: "hand.wave.fill")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Mactivate")
                    .font(Theme.font(.title))
            }

            StatusPill(
                symbolName: statusSymbol,
                title: model.status.headline,
                tone: model.status.headlineTone
            )

            Spacer(minLength: Metrics.Spacing.snug)

            Picker("Section", selection: $model.panel.tab) {
                ForEach(PanelTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .onChange(of: model.panel.tab) { _, _ in
                model.panel.handle(.userInteracted)
            }

            Button {
                model.panel.handle(.dismissRequested)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close the workspace (Escape)")
            .accessibilityLabel("Close the workspace")
        }
        .padding(.horizontal, Metrics.Spacing.roomy)
        .padding(.bottom, Metrics.Spacing.regular)
    }

    private var statusSymbol: String {
        switch model.status.headlineTone {
        case .ready: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .unavailable: return "minus.circle.fill"
        case .neutral: return "pause.circle.fill"
        case .experimental: return "questionmark.circle.fill"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.panel.tab {
        case .taps:
            NotchTapsSection(model: model, openMainWindow: openMainWindow)
        case .macroPad:
            NotchMacroPadSection(model: model, runningSlotID: $runningSlotID, openMainWindow: openMainWindow)
        case .status:
            NotchStatusSection(model: model, openMainWindow: openMainWindow)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Metrics.Spacing.snug) {
            if let error = model.persistenceError {
                ExplainerCallout(
                    symbolName: "exclamationmark.icloud",
                    title: "Your change was not saved",
                    message: error,
                    tone: .failure,
                    primaryActionTitle: "OK",
                    primaryAction: { model.dismissPersistenceError() }
                )
                .padding(.horizontal, Metrics.Spacing.roomy)
            }

            HStack(spacing: Metrics.Spacing.regular) {
                if let undoLabel = model.undoLabel {
                    Button(undoLabel) { model.undoLastEdit() }
                        .buttonStyle(.link)
                        .keyboardShortcut("z", modifiers: .command)
                }

                Spacer(minLength: 0)

                Button("Calibrate…") { openMainWindow(.calibration) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("All Settings…") { openMainWindow(.overview) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(",", modifiers: .command)
            }
            .padding(.horizontal, Metrics.Spacing.roomy)
        }
        .padding(.top, Metrics.Spacing.snug)
    }
}
#endif
