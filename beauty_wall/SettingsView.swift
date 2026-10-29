import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case credentials
    case sources

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .credentials: return "凭证"
        case .sources: return "来源"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .credentials: return "key"
        case .sources: return "square.3.layers.3d"
        }
    }
}

struct SettingsView: View {
    @SceneStorage("settings.selected.section") private var selectedSectionRaw = SettingsSection.general.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selectedSection: SettingsSection {
        SettingsSection(rawValue: selectedSectionRaw) ?? .general
    }

    private var selectedSectionBinding: Binding<SettingsSection?> {
        Binding<SettingsSection?>(
            get: { selectedSection },
            set: { selectedSectionRaw = ($0 ?? .general).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: selectedSectionBinding) {
                Section("设置") {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.title, systemImage: section.symbolName)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
            .navigationTitle("设置")
        } detail: {
            Group {
                switch selectedSection {
                case .general:
                    GeneralSettingsPane()
                case .credentials:
                    CredentialsSettingsPane()
                case .sources:
                    SourcesSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppSettingsStore())
    }
}
