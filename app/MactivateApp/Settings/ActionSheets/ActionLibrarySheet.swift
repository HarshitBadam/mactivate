import MactivateRuntime
import SwiftUI

struct ActionLibrarySheet: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddAction = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            HStack(alignment: .top, spacing: SettingsMetrics.fieldGap) {
                VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                    Text("Action Library")
                        .font(.title2.bold())
                    Text(
                        "\(state.actions.count) action" +
                            (state.actions.count == 1 ? "" : "s") +
                            " available. Test one before assigning it to a gesture or slot."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: SettingsMetrics.fieldGap)
                Button {
                    showingAddAction = true
                } label: {
                    Label("New Action", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVStack(spacing: SettingsMetrics.iconGap) {
                    ForEach(state.actions) { action in
                        actionRow(action)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            if let error = state.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(SettingsMetrics.pageInset)
        .frame(width: 480, height: 560)
        .background(SettingsBackdrop())
        .sheet(isPresented: $showingAddAction) {
            AddActionSheet(
                state: state,
                actions: actions,
                isPresented: $showingAddAction
            )
        }
    }

    private func actionRow(_ action: AppActionDefinition) -> some View {
        HStack(spacing: SettingsMetrics.controlGap) {
            Image(systemName: action.kind.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(action.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(actionDetail(action))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                actions.testAction(action.id)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Test \(action.name)")
            if action.id != AppActionDefinition.showPanel.id {
                Button(role: .destructive) {
                    actions.deleteAction(action.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete \(action.name)")
            }
        }
        .padding(.vertical, SettingsMetrics.controlGap)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("action-library-\(action.id.rawValue)")
    }

    private func actionDetail(_ action: AppActionDefinition) -> String {
        switch action.kind {
        case .showPanel: return "Built in"
        case .application(let identifier): return identifier
        case .webURL(let value): return value
        case .shortcut: return "Shortcut"
        }
    }
}
