import SwiftUI

struct CairnSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            GeneralPane(settings: app.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearancePane(settings: app.settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            FilesPane(settings: app.settings)
                .tabItem { Label("Files", systemImage: "doc") }
            AdvancedPane()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 360)
    }
}

private struct GeneralPane: View {
    @Bindable var settings: SettingsStore
    var body: some View {
        Form {
            Picker("Start with", selection: $settings.startFolder) {
                ForEach(SettingsStore.StartFolder.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            Toggle("Restore tabs on relaunch", isOn: $settings.restoreTabs)
        }
        .padding(20)
    }
}

private struct AppearancePane: View {
    @Bindable var settings: SettingsStore
    var body: some View {
        Form {
            Picker("Font size", selection: $settings.fontSize) {
                ForEach(SettingsStore.FontSize.allCases) { s in
                    Text(s.rawValue.capitalized).tag(s)
                }
            }
            LabeledContent("Theme") {
                Text("Glass (Blue) — more themes in a future release.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

private struct FilesPane: View {
    @Bindable var settings: SettingsStore
    var body: some View {
        Form {
            Picker("Default sort", selection: $settings.defaultSortField) {
                Text("Name").tag("name")
                Text("Size").tag("size")
                Text("Modified").tag("modified")
            }
            Toggle("Ascending", isOn: $settings.defaultSortAscending)
            Toggle("Show hidden files by default", isOn: $settings.showHiddenByDefault)
            Toggle("Show Git status column", isOn: $settings.showGitColumn)
        }
        .padding(20)
    }
}

private struct AdvancedPane: View {
    var body: some View {
        Form {
            LabeledContent("Index cache") {
                Text("~/Library/Caches/Cairn")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Button("Rebuild Index") {
                // Phase 2 will wire an FFI entry point. For now this is an
                // inert affordance so the Settings layout is finalised.
            }
            .disabled(true)
        }
        .padding(20)
    }
}
