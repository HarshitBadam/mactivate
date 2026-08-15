import MactivateRuntime
import SwiftUI

struct ActionPicker: View {
    @Binding var selection: ActionIdentifier?
    let actions: [AppActionDefinition]
    let includeShowPanel: Bool

    var body: some View {
        Picker("", selection: $selection) {
            Text("None").tag(ActionIdentifier?.none)
            ForEach(filteredActions) { action in
                Label(action.name, systemImage: action.kind.symbolName)
                    .tag(Optional(action.id))
            }
            if let selection,
               !filteredActions.contains(where: { $0.id == selection }) {
                Text("Missing action").tag(Optional(selection))
            }
        }
        .labelsHidden()
    }

    private var filteredActions: [AppActionDefinition] {
        actions.filter {
            includeShowPanel || $0.id != AppActionDefinition.showPanel.id
        }
    }
}
