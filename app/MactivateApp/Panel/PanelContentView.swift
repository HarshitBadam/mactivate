import SwiftUI

struct AppViewActions {
    let performAction: (AppActionDefinition) -> Void
    let showSettings: (Int?) -> Void
}

struct PanelContentView: View {
    @ObservedObject var state: AppState
    let actions: AppViewActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quickActions
            if state.actionError != nil || state.recentWarning != nil {
                statusFooter
            }
        }
        .padding(.horizontal, 2)
        .frame(width: 358, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mactivate Notch Panel")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: Circle())

            Text("Notch Panel")
                .font(.headline)

            Spacer()

            Button { actions.showSettings(nil) } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))
            .help("Configuration")
            .accessibilityLabel("Open Mactivate Configuration Window")
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
                    Button { actions.showSettings(index) } label: {
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
            if let error = state.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityLabel("Action error: \(error)")
            } else if let warning = state.recentWarning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct QuickActionButtonStyle: ButtonStyle {
    var isPlaceholder = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                isPlaceholder ? .white.opacity(0.55) : .white
            )
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
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
                showSettings: { _ in }
            )
        )
        .padding(30)
    }
}
#endif
