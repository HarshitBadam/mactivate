import SwiftUI

struct AppViewActions {
    let performAction: (AppActionDefinition) -> Void
    let showSettings: () -> Void
}

struct PanelContentView: View {
    @ObservedObject var state: AppState
    let actions: AppViewActions

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            notchConnector

            VStack(alignment: .leading, spacing: 14) {
                header
                quickActions
                statusFooter
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 388, height: 292, alignment: .top)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.10))
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mactivate quick actions")
    }

    private var notchConnector: some View {
        Capsule(style: .continuous)
            .fill(.black)
            .frame(width: 116, height: 8)
            .padding(.top, 2)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Mactivate")
                    .font(.headline)
                Text(state.tapStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: actions.showSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Open Mactivate settings")
        }
    }

    private var quickActions: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(Array(state.quickActions.enumerated()), id: \.offset) {
                index, action in
                if let action {
                    Button {
                        actions.performAction(action)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: action.kind.symbolName)
                                .frame(width: 20)
                            Text(action.name)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(QuickActionButtonStyle())
                    .accessibilityIdentifier("quickAction.\(index)")
                } else {
                    Button(action: actions.showSettings) {
                        HStack(spacing: 9) {
                            Image(systemName: "plus")
                                .frame(width: 20)
                            Text("Add action")
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(QuickActionButtonStyle(isPlaceholder: true))
                    .accessibilityLabel("Configure quick action \(index + 1)")
                }
            }
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(state.panelHintStatus, systemImage: "sun.min")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let error = state.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityLabel("Action error: \(error)")
            } else if let warning = state.recentWarning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

private struct QuickActionButtonStyle: ButtonStyle {
    var isPlaceholder = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPlaceholder ? .secondary : .primary)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
            .scaleEffect(
                !reduceMotion && configuration.isPressed ? 0.98 : 1
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.10),
                value: configuration.isPressed
            )
    }
}

#if DEBUG
struct PanelContentView_Previews: PreviewProvider {
    static var previews: some View {
        PanelContentView(
            state: AppState(),
            actions: AppViewActions(
                performAction: { _ in },
                showSettings: {}
            )
        )
        .padding(30)
    }
}
#endif
