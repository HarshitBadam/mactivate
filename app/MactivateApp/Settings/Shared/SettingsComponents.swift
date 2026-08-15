import SwiftUI

enum SettingsMetrics {
    static let hairline: CGFloat = 1
    static let compact: CGFloat = 4
    static let iconGap: CGFloat = 6
    static let controlGap: CGFloat = 10
    static let fieldGap: CGFloat = 14
    static let cardInset: CGFloat = 20
    static let headerToCard: CGFloat = 12
    static let pageInset: CGFloat = 28
    static let paneTopInset: CGFloat = 18
    static let sectionGap: CGFloat = 30
    static let majorGap: CGFloat = 32
    static let rowHeight: CGFloat = 44
    static let cardRadius: CGFloat = 10
}

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var accessory: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.fieldGap) {
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: SettingsMetrics.fieldGap)
            accessory
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.headerToCard) {
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
                content
            }
            .padding(SettingsMetrics.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
            )
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: SettingsMetrics.fieldGap) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: SettingsMetrics.fieldGap)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

struct SettingsStatusBadge: View {
    let title: String
    let ready: Bool

    var body: some View {
        Label(
            title,
            systemImage: ready
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(ready ? Color.secondary : Color.orange)
        .padding(.horizontal, SettingsMetrics.controlGap)
        .padding(.vertical, SettingsMetrics.compact)
        .background(
            ready
                ? Color.secondary.opacity(0.12)
                : Color.orange.opacity(0.12),
            in: Capsule()
        )
    }
}

struct SettingsBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}
