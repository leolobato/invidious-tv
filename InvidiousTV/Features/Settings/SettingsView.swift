import SwiftUI
import InvidiousKit

struct SettingsView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var instanceText = ""
    @State private var instanceStatus: String?
    @State private var isCheckingInstance = false
    @State private var renameText = ""
    @State private var showRename = false
    @State private var showReauth = false
    @State private var confirmRemove = false

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Profile") {
                LabeledContent("Name", value: session.profile.name)
                LabeledContent("Username", value: session.profile.username)
                LabeledContent("Instance", value: session.profile.instanceURL.absoluteString)
                Button("Rename Profile") {
                    renameText = session.profile.name
                    showRename = true
                }
                Button("Sign In Again") { showReauth = true }
                Button("Switch Profile") { app.deactivate() }
                Button("Remove Profile", role: .destructive) { confirmRemove = true }
            }

            Section("Playback") {
                Picker("Maximum quality", selection: $settings.maxQuality) {
                    ForEach(AppSettings.qualityOptions, id: \.self) { height in
                        Text(AppSettings.qualityLabel(height)).tag(height)
                    }
                }
                Picker("Default speed", selection: $settings.defaultSpeed) {
                    ForEach(AppSettings.speedOptions, id: \.self) { speed in
                        Text(speed == 1 ? "Normal" : String(format: "%g×", speed)).tag(speed)
                    }
                }
                Toggle("Proxy media through instance", isOn: $settings.proxyMedia)
                Text("Proxying routes video data through the Invidious server. Turn it off to stream directly from YouTube's servers when the instance is on a slow link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Instance for new profiles") {
                TextField("Instance URL", text: $instanceText)
                    .keyboardType(.URL)
                    .onSubmit { Task { await checkInstance() } }
                Button {
                    Task { await checkInstance() }
                } label: {
                    if isCheckingInstance {
                        ProgressView()
                    } else {
                        Text("Check and Save")
                    }
                }
                .disabled(isCheckingInstance)
                if let instanceStatus {
                    Text(instanceStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("App version", value: Self.appVersion)
                LabeledContent("Player", value: "MPV")
            }
        }
        .navigationTitle("Settings")
        .onAppear { instanceText = app.settings.instanceURLString }
        .alert("Rename Profile", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { app.rename(session.profile, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Remove \(session.profile.name)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { app.removeProfile(session.profile) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the profile from this Apple TV, including its resume positions. Your Invidious account is not affected.")
        }
        .fullScreenCover(isPresented: $showReauth) {
            LoginView(mode: .reauthenticate(session.profile))
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func checkInstance() async {
        guard let url = AppSettings.normalizedURL(from: instanceText) else {
            instanceStatus = "That does not look like a valid URL."
            return
        }
        isCheckingInstance = true
        defer { isCheckingInstance = false }
        do {
            let stats = try await InvidiousClient(baseURL: url).stats()
            app.settings.instanceURLString = url.absoluteString
            instanceText = url.absoluteString
            instanceStatus = "Connected to \(stats.software.name) \(stats.software.version)."
        } catch {
            instanceStatus = "Could not reach the instance: \(error.localizedDescription)"
        }
    }
}
