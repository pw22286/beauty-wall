import SwiftUI

enum SettingsLayout {
    static let windowWidth: CGFloat = 1024
    static let windowHeight: CGFloat = 700
    static let contentMaxWidth: CGFloat = 900
    static let sectionSpacing: CGFloat = 16
    static let rowLabelWidth: CGFloat = 120
    static let settingsSidebarWidth: CGFloat = 220
    static let sourcesSidebarWidth: CGFloat = 320
    static let sourcesDetailMaxWidth: CGFloat = 780
    static let cardCornerRadius: CGFloat = 12
}

struct SettingsPaneScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .frame(maxWidth: SettingsLayout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: SettingsLayout.rowLabelWidth, alignment: .leading)
            content
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum SettingsFeedbackTone {
    case neutral
    case success
    case warning
    case error

    var symbolName: String {
        switch self {
        case .neutral: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct SettingsFeedback: Equatable {
    let tone: SettingsFeedbackTone
    let text: String
}

struct SettingsFeedbackBanner: View {
    let feedback: SettingsFeedback

    var body: some View {
        Label(feedback.text, systemImage: feedback.tone.symbolName)
            .font(.caption)
            .foregroundStyle(feedback.tone.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(feedback.text)
    }
}

private struct SettingsCardSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
        )
    }
}
