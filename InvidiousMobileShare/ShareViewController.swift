import UIKit
import SwiftUI
import UniformTypeIdentifiers
import InvidiousKit

/// Share sheet entry: takes a YouTube link and opens it in the app.
final class ShareViewController: UIViewController {
    private var videoID: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await loadInput() }
    }

    private func loadInput() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var candidates: [String] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    candidates.append(url.absoluteString)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    candidates.append(text)
                }
            }
            if let text = item.attributedContentText?.string { candidates.append(text) }
        }
        let link = candidates.lazy.compactMap { YouTubeLink.parse($0) }.first
        if case .video(let id, _) = link {
            videoID = id
            SharedLinkInbox().store(videoID: id)
        }
        show()
    }

    private func show() {
        let content = ShareResultView(
            videoID: videoID,
            open: { [weak self] in self?.openApp() },
            done: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        let host = UIHostingController(rootView: content)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        if videoID != nil {
            openApp()
        }
    }

    /// Opens the app through the responder chain; the pending link file is the fallback.
    private func openApp() {
        guard let id = videoID else { return }
        let url = AppLink.video(id)
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] _ in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
                return
            }
            responder = current.next
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

struct ShareResultView: View {
    let videoID: String?
    let open: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: videoID == nil ? "exclamationmark.triangle" : "play.rectangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(videoID == nil ? .orange : .red)
            Text(videoID == nil ? "This is not a YouTube video link." : "Opening in Invidious…")
                .font(.headline)
            if videoID != nil {
                Text("If the app did not open, tap Open. The video will also be waiting the next time you open Invidious.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Invidious", action: open).buttonStyle(.borderedProminent)
            }
            Button("Done", action: done)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
