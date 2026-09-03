import SwiftUI
import InvidiousKit

/// Username and password sign-in for a new profile or an expired session.
struct LoginView: View {
    enum Mode: Identifiable {
        case newProfile
        case reauthenticate(Profile)

        var id: String {
            switch self {
            case .newProfile: return "new"
            case .reauthenticate(let profile): return profile.id.uuidString
            }
        }
    }

    let mode: Mode

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var instance = ""
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case instance, username, password, name }

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 24) {
                if case .newProfile = mode {
                    TextField("Instance URL", text: $instance)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .instance)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .focused($focusedField, equals: .username)
                }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit(submit)
                if case .newProfile = mode {
                    TextField("Profile name (optional)", text: $displayName)
                        .focused($focusedField, equals: .name)
                        .onSubmit(submit)
                }
            }
            #if os(tvOS)
            .textFieldStyle(.plain)
            .frame(width: 700)
            #else
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(maxWidth: 500)
            .padding(.horizontal, 24)
            #endif

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 800)
            }

            HStack(spacing: 30) {
                Button("Cancel") { dismiss() }
                Button {
                    submit()
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(isWorking || !canSubmit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(tvOS)
        .background(Color.black)
        #endif
        .onAppear {
            switch mode {
            case .newProfile:
                instance = app.settings.instanceURLString
                focusedField = .username
            case .reauthenticate:
                focusedField = .password
            }
        }
    }

    private var title: String {
        switch mode {
        case .newProfile: return "Sign in to Invidious"
        case .reauthenticate(let profile): return "Welcome back, \(profile.name)"
        }
    }

    private var subtitle: String {
        switch mode {
        case .newProfile: return "Use the username and password of your Invidious account."
        case .reauthenticate: return "Your session expired. Enter your password to continue."
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .newProfile:
            return AppSettings.normalizedURL(from: instance) != nil && !username.isEmpty && !password.isEmpty
        case .reauthenticate:
            return !password.isEmpty
        }
    }

    private func submit() {
        guard canSubmit, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                switch mode {
                case .newProfile:
                    guard let url = AppSettings.normalizedURL(from: instance) else { return }
                    app.settings.instanceURLString = url.absoluteString
                    let profile = try await app.addProfile(name: displayName, username: username, password: password, instanceURL: url)
                    try app.activate(profile)
                case .reauthenticate(let profile):
                    try await app.reauthenticate(profile, password: password)
                    if app.active == nil {
                        try app.activate(profile)
                    }
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
