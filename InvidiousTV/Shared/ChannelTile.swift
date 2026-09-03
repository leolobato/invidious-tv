import SwiftUI
import InvidiousKit

/// Round avatar with the channel name, used by the Channels grid.
struct ChannelTile: View {
    let channel: SubscribedChannel

    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink(value: Route.channel(id: channel.authorId, name: channel.author)) {
            VStack(spacing: 14) {
                ChannelAvatar(channelID: channel.authorId, name: channel.author, size: 160)
                Text(channel.author)
                    .font(.callout.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .buttonStyle(.card)
    }
}

/// Channel avatar image with an initials fallback while it loads.
struct ChannelAvatar: View {
    let channelID: String
    let name: String
    var size: CGFloat = 80
    var url: URL? = nil

    @Environment(AppModel.self) private var app

    var body: some View {
        let resolved = url ?? app.channelAvatars.url(for: channelID)
        ZStack {
            Circle().fill(ProfilePalette.color(for: channelID))
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
            if let resolved {
                RemoteImage(url: resolved)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .task(id: channelID) {
            guard url == nil, let client = app.active?.client else { return }
            await app.channelAvatars.load(channelID: channelID, using: client)
        }
    }

    private var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true || $0.first?.isNumber == true }.prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? String(name.prefix(1)).uppercased() : letters.joined()
    }
}
