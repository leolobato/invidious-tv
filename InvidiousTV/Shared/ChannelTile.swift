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
