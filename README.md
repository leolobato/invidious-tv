# Invidious TV

Invidious TV is a tvOS and iOS client for [Invidious](https://invidious.io), the open-source alternative
front end to YouTube. Invidious runs on a server, either a public instance or one you host yourself, and
exposes YouTube without ads or tracking. This app talks to one instance and signs in to accounts on it,
so subscriptions, playlists and watch history are the same ones you see on the instance's website.

The interface follows the YouTube apps for Apple TV and iPhone: a profile picker for the household, a
home screen with recommendations, a chronological subscriptions feed, and a full-screen player. It is
written in SwiftUI for tvOS 26 and iOS 26.

This is an unofficial client. It is not affiliated with or endorsed by the Invidious project, and the
Invidious name and logo belong to that project.

## Features

- Profiles: several household members, each signed in to their own Invidious account on the instance.
- Sign in with username and password, or on Apple TV by scanning a QR code with your phone and approving
  in the instance's website.
- Home with recommendations built from your history, plus the latest uploads from your subscriptions.
- Subscriptions feed, channel browser with sorting and a name filter, and channel pages.
- Search with suggestions; paste a YouTube link or video ID to open it directly.
- Playlists and Watch Later, with Save from any video, and the account's watch history.
- Player with scrubbing and thumbnail previews, quality, speed, captions, and audio language selection
  so auto-dubbed videos play in their original language.
- Resume where you left off, on any of your devices, with positions synced through iCloud.
- Autoplay of the next video with a countdown.
- SponsorBlock skipping of sponsor and self-promotion segments.
- Comments on the video page, and tappable links in descriptions.
- Optional Hide Shorts filter.
- Apple TV Top Shelf with Continue Watching and the latest subscriptions, refreshed in the background.
- iOS share extension: send a YouTube link from any app to open it here.

## Planned

- Livestreams. Instances running invidious-companion currently return no playable manifest for live
  videos, so live playback waits on a fix there.
- A macOS app on the same core.

## Build

```sh
brew install xcodegen
cp Configuration/LocalSigning.xcconfig.example Configuration/LocalSigning.xcconfig  # edit values
xcodegen generate
open InvidiousTV.xcodeproj
```

`LocalSigning.xcconfig` holds your team, bundle ID and, optionally, `DEFAULT_INSTANCE_URL`, the instance
offered on the login screen (slashes escaped as `http:/$()/host:port`). Without it the user types the
instance URL on first launch. The bundle ID also names the app group, the shared keychain group and the
unified-log subsystem.

Package tests run on the Mac, no simulator needed:

```sh
cd Packages/InvidiousKit && swift test
```

Schemes: `InvidiousTV` (Apple TV) and `InvidiousMobile` (iPhone and iPad). The iOS bundle ID is the tvOS
one with `.mobile` appended.

## Playback

Video plays through libmpv via [MPVKit](https://github.com/yattee/MPVKit), the same player component
[Yattee](https://github.com/yattee/yattee) uses. The app picks the best adaptive video stream the device
can decode, up to 4K, plus a separate audio stream, and prefers the original audio language when
YouTube offers dubs. On devices, mpv renders through OpenGL ES. In the simulator it falls back to mpv's
software renderer, capped at 720p.

## License and third-party notices

Invidious TV is free software under the [GNU GPL-3.0](LICENSE), a consequence of linking the GPL build of
MPVKit. It uses:

- [MPVKit](https://github.com/yattee/MPVKit) (GPL-3.0), which bundles [mpv](https://mpv.io) and FFmpeg (GPL/LGPL).
- [Nuke](https://github.com/kean/Nuke) (MIT) for image loading and caching.
- Segment data from [SponsorBlock](https://sponsor.ajay.app) (CC BY-NC-SA 4.0).
- The API of [Invidious](https://github.com/iv-org/invidious) (AGPL-3.0). The app icon is derived from the
  Invidious logo.
