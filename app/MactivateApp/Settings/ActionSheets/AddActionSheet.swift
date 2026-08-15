import MactivateRuntime
import SwiftUI

struct AddActionSheet: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions
    @Binding var isPresented: Bool

    @State private var selection = 0
    @State private var webName = ""
    @State private var webAddress = "https://"
    @State private var shortcutName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text("New Action")
                    .font(.title2.bold())
                Text("Choose one focused response for a tap or Notch Panel slot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("Action type", selection: $selection) {
                Text("Application").tag(0)
                Text("Web Link").tag(1)
                Text("Shortcut").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Action type")

            Group {
                switch selection {
                case 0:
                    actionTypeCard(
                        symbol: "app.dashed",
                        title: "Launch an application",
                        detail: "Choose any installed macOS application."
                    ) {
                        Button("Choose Application…") {
                            if actions.addApplication() {
                                isPresented = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case 1:
                    actionTypeCard(
                        symbol: "link",
                        title: "Open a web link",
                        detail: "Only HTTP and HTTPS addresses are accepted."
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: SettingsMetrics.fieldGap
                        ) {
                            labeledField("Name") {
                                TextField("Documentation", text: $webName)
                            }
                            labeledField("Address") {
                                TextField(
                                    "https://example.com",
                                    text: $webAddress
                                )
                            }
                            HStack {
                                Spacer()
                                Button("Add Web Link") {
                                    if actions.addWebURL(
                                        webName,
                                        webAddress
                                    ) {
                                        isPresented = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(
                                    webName.trimmingCharacters(
                                        in: .whitespaces
                                    ).isEmpty
                                )
                            }
                        }
                    }
                default:
                    actionTypeCard(
                        symbol: "command",
                        title: "Run a macOS Shortcut",
                        detail: "Choose from the Shortcuts available on this Mac."
                    ) {
                        Picker("Shortcut", selection: $shortcutName) {
                            Text("Choose a Shortcut").tag("")
                            ForEach(state.availableShortcuts, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        HStack {
                            Button {
                                actions.refreshShortcuts()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            Button("Add Shortcut") {
                                if actions.addShortcut(shortcutName) {
                                    isPresented = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                shortcutName.trimmingCharacters(in: .whitespaces).isEmpty
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if let error = state.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
            }
        }
        .padding(SettingsMetrics.pageInset)
        .frame(width: 576, height: 384)
        .background(SettingsBackdrop())
        .onAppear(perform: actions.refreshShortcuts)
    }

    private func actionTypeCard<Content: View>(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.iconGap) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
