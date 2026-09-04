import SwiftUI
import CoreImage.CIFilterBuiltins
import InvidiousKit

/// QR-code sign-in: the phone opens the instance's authorize page and Invidious sends the token back
/// to a listener on this Apple TV.
struct PhoneLoginView: View {
    let instanceURL: URL
    /// When set, the token replaces this profile's credential instead of creating a new profile.
    var existingProfile: Profile?
    /// Called after the profile is active and this screen should go away along with its parent.
    var onComplete: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var authorizeURL: URL?
    @State private var qrImage: UIImage?
    @State private var status: Status = .starting
    @State private var server: TokenCallbackServer?
    @State private var attempt = 0

    private enum Status: Equatable {
        case starting
        case waiting
        case verifying
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Text(existingProfile == nil ? "Sign in with your phone" : "Sign in again with your phone")
                    .font(.largeTitle.weight(.semibold))
                Text("Scan the code, sign in to Invidious on your phone and tap Yes. Your phone must be on the same network as this Apple TV.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .frame(width: 440, height: 440)
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 400, height: 400)
                } else {
                    ProgressView()
                }
            }

            VStack(spacing: 12) {
                switch status {
                case .starting:
                    Text("Preparing…").foregroundStyle(.secondary)
                case .waiting:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for your phone…")
                    }
                    .foregroundStyle(.secondary)
                    if let authorizeURL {
                        Text("Or open \(authorizeURL.absoluteString) on your phone.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .frame(maxWidth: 1200)
                    }
                case .verifying:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking with the instance…")
                    }
                    .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)
                }
            }
            .frame(minHeight: 80)

            HStack(spacing: 30) {
                Button("Cancel") { dismiss() }
                if case .failed = status {
                    Button("Try Again") { attempt += 1 }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(id: attempt) {
            await run()
        }
        .onDisappear {
            server?.stop()
        }
    }

    private func run() async {
        server?.stop()
        status = .starting
        qrImage = nil
        let server = TokenCallbackServer()
        self.server = server
        do {
            let port = try await server.start()
            guard let host = LocalNetworkAddress.ipv4Addresses().first else {
                throw PhoneLoginError.noNetwork
            }
            guard let callback = TokenLogin.callbackURL(host: host, port: port),
                  let url = TokenLogin.authorizeURL(instance: instanceURL, callback: callback) else {
                throw PhoneLoginError.badURL
            }
            authorizeURL = url
            qrImage = Self.qrCode(for: url.absoluteString)
            status = .waiting
            let result = try await server.waitForResult()
            server.stop()
            status = .verifying
            let profile = try await app.completeTokenLogin(result, instanceURL: instanceURL, existing: existingProfile)
            if app.active == nil || app.active?.profile.id == profile.id {
                try app.activate(profile)
            }
            onComplete()
            dismiss()
        } catch is CancellationError {
            server.stop()
        } catch TokenCallbackServer.ServerError.stopped {
            // Cancelled by the user or superseded by a retry.
        } catch {
            server.stop()
            status = .failed(error.localizedDescription)
        }
    }

    private enum PhoneLoginError: LocalizedError {
        case noNetwork
        case badURL

        var errorDescription: String? {
            switch self {
            case .noNetwork: return "This Apple TV does not seem to be connected to a network."
            case .badURL: return "Could not build the sign-in link for this instance."
            }
        }
    }

    static func qrCode(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = 400 / max(output.extent.width, 1)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
