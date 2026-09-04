# Invidious TV

Invidious TV is a tvOS and iOS client for [Invidious](https://invidious.io), the open-source alternative
front end to YouTube. Invidious runs on a server, either a public instance or one you host yourself, and
exposes YouTube without ads or tracking. This app talks to one instance and signs in to accounts on it,
so subscriptions, playlists and watch history are the same ones you see on the instance's website.

The interface follows the YouTube apps for Apple TV and iPhone: a profile picker for the household, a
home screen with recommendations, a chronological subscriptions feed, and a full-screen player. It is
written in SwiftUI for tvOS 26 and iOS 26.

**This is an unofficial client.** It is not affiliated with or endorsed by the Invidious project, and the
Invidious name and logo belong to that project.

## Features

- **Profiles** for the household, each signed in to its own Invidious account.
- **Phone sign-in** on Apple TV: scan a QR code and approve on the instance's website, no typing.
- **Home** with recommendations from your history and the latest uploads from your subscriptions.
- **Subscriptions and channels**, with sorting and a name filter. Channel pages list the channel's playlists.
- **Search** with suggestions; paste a YouTube link or video ID to open it.
- **Playlists, Watch Later and watch history**, shared with the instance's website.
- **Player** with scrubbing previews, quality, speed, captions and audio language, so auto-dubbed videos
  play in their original language. Swipe down on the remote for these options.
- **Resume anywhere**: positions sync between your devices through iCloud.
- **Autoplay** of the next video with a countdown.
- **SponsorBlock** skipping of sponsor and self-promotion segments.
- **Comments** and tappable description links.
- **Top Shelf** on Apple TV with Continue Watching and new uploads, refreshed in the background.
- **Share extension** on iOS: send a YouTube link from any app to open it here.

## Planned

- **Livestreams.** Instances running invidious-companion return no playable manifest for live videos yet.
- **macOS app** on the same core.
- **Hide Shorts.** Invidious does not flag Shorts, so a reliable filter needs more than a duration guess.

## Build

### Configure signing and your instance

Copy `Configuration/LocalSigning.xcconfig.example` to `Configuration/LocalSigning.xcconfig` (gitignored) and
edit it:

```
DEVELOPMENT_TEAM = ABCDE12345                      # your Apple Developer team ID
APP_BUNDLE_ID = com.yourcompany.invidioustv         # tvOS bundle ID; iOS uses it with .mobile appended
DEFAULT_INSTANCE_URL = http:/$()/192.168.1.10:3000  # optional; offered on the login screen
```

`DEFAULT_INSTANCE_URL` is optional, and without it the user types the instance URL on first launch. The
odd `http:/$()/` escapes the slashes, which xcconfig would otherwise read as a comment. The bundle ID also
names the app group, the shared keychain group and the unified-log subsystem.

### Generate and build

```sh
brew install xcodegen
xcodegen generate
open InvidiousTV.xcodeproj
```

Schemes: `InvidiousTV` (Apple TV) and `InvidiousMobile` (iPhone and iPad).

Package tests run on the Mac, no simulator needed:

```sh
cd Packages/InvidiousKit && swift test
```

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
