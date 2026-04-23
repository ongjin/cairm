import SwiftUI

struct ConnectSheetView: View {
    @Bindable var model: ConnectSheetModel
    var onConnect: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Server").font(.headline)
            Divider()

            LabeledContent("Server") {
                HStack {
                    TextField("deploy@prod-api", text: $model.server)
                    Text(":")
                    TextField("22", text: $model.port).frame(width: 48)
                }
            }
            LabeledContent("Path") {
                TextField("/var/log/nginx", text: $model.path)
            }

            GroupBox("Auth") {
                VStack(alignment: .leading) {
                    Picker("", selection: $model.authMode) {
                        Text("Agent").tag(ConnectSheetModel.AuthMode.agent)
                        Text("Key file").tag(ConnectSheetModel.AuthMode.keyFile)
                    }.pickerStyle(.radioGroup)
                    if model.authMode == .keyFile {
                        HStack {
                            TextField("~/.ssh/id_ed25519", text: $model.keyFile)
                            Button("Browse\u{2026}") { pickKeyFile() }
                        }
                    }
                }
            }

            DisclosureGroup("Advanced", isExpanded: $model.showAdvanced) {
                TextField("Custom ProxyCommand", text: $model.proxyCommand)
            }

            Toggle("Save to ~/.ssh/config as:", isOn: $model.saveToConfig)
            if model.saveToConfig {
                TextField("prod-api", text: $model.nickname)
            }

            if let err = model.error {
                Text(err).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Connect", action: onConnect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.server.isEmpty || model.connecting)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        panel.directoryURL = URL(fileURLWithPath: "\(home)/.ssh")
        if panel.runModal() == .OK, let url = panel.url {
            model.keyFile = url.path
        }
    }
}
