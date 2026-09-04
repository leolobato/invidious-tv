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
    @State private var showPhoneLogin = false
    @FocusState private var focusedField: Field?

    private enum Field { case instance, username, password, name }

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        mobileBody
        #endif
    }

    // MARK: - iPhone and iPad

    #if os(iOS)
    private var mobileBody: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.title2.weight(.semibold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                if case .newProfile = mode {
                    Section("Instance") {
                        field(systemImage: "server.rack") {
                            TextField("https://invidious.example.com", text: $instance)
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .instance)
                                .onSubmit { focusedField = .username }
                        }
                    }
                }

                Section("Account") {
                    if case .newProfile = mode {
                        field(systemImage: "person") {
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .username)
                                .onSubmit { focusedField = .password }
                        }
                    } else if case .reauthenticate(let profile) = mode {
                        field(systemImage: "person") {
                            Text(profile.username)
                                .foregroundStyle(.secondary)
                        }
                    }
                    field(systemImage: "lock") {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .submitLabel(reauthProfile == nil ? .next : .go)
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                                if reauthProfile == nil { focusedField = .name } else { submit() }
                            }
                    }
                }

                if case .newProfile = mode {
                    Section {
                        field(systemImage: "textformat") {
                            TextField("Profile name", text: $displayName)
                                .textContentType(.nickname)
                                .submitLabel(.go)
                                .focused($focusedField, equals: .name)
                                .onSubmit(submit)
                        }
                    } footer: {
                        Text("Shown on the profile picker. Defaults to the username.")
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else {
                                Text("Sign In")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || !canSubmit)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onAppear(perform: prepare)
    }

    private func field<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            content()
        }
    }
    #endif

    // MARK: - Apple TV

    #if os(tvOS)
    private var tvBody: some View {
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
            .textFieldStyle(.plain)
            .frame(width: 700)

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
                Button {
                    showPhoneLogin = true
                } label: {
                    Label("Sign in with your phone", systemImage: "qrcode")
                }
                .disabled(isWorking || phoneLoginInstance == nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .fullScreenCover(isPresented: $showPhoneLogin) {
            if let phoneLoginInstance {
                PhoneLoginView(instanceURL: phoneLoginInstance, existingProfile: reauthProfile) {
                    dismiss()
                }
            }
        }
        .onAppear {
            prepare()
            #if DEBUG
            if ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_PHONE_LOGIN"] != nil {
                showPhoneLogin = true
            }
            #endif
        }
    }
    #endif

    private func prepare() {
        switch mode {
        case .newProfile:
            instance = app.settings.instanceURLString
            focusedField = .username
        case .reauthenticate:
            focusedField = .password
        }
    }

    private var reauthProfile: Profile? {
        if case .reauthenticate(let profile) = mode { return profile }
        return nil
    }

    /// Instance the phone sign-in targets: the field for new profiles, the profile's own otherwise.
    private var phoneLoginInstance: URL? {
        switch mode {
        case .newProfile: return AppSettings.normalizedURL(from: instance)
        case .reauthenticate(let profile): return profile.instanceURL
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
        #if os(tvOS)
        case .newProfile: return "Use the username and password of your Invidious account, or sign in from your phone."
        #else
        case .newProfile: return "Use the username and password of your Invidious account."
        #endif
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
