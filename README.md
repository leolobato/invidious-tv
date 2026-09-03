# Invidious TV

A tvOS and iOS client for a self-hosted [Invidious](https://github.com/iv-org/invidious) instance, in
the style of the YouTube apps. SwiftUI, tvOS 26 and iOS 26, MPV playback. See `docs/PRD-v1.md` and
`docs/PRD-v2.md` for the product requirements.

## Layout

| Path | Purpose |
| --- | --- |
| `project.yml` | XcodeGen spec. Run `xcodegen generate` after adding files. |
| `Configuration/` | Signing. `Base.xcconfig` is committed; copy `LocalSigning.xcconfig.example` to `LocalSigning.xcconfig` and fill in your team and bundle ID. |
| `Packages/InvidiousKit` | Platform-agnostic Swift package: API client, models, login, profiles, resume store, home feed builder, stream selection, search, playlists, comments, SponsorBlock. |
| `Shared/` | App code compiled into both apps: app model, settings, stores, view models, MPV player core, shared views. |
| `InvidiousTV/` | tvOS views and remote handling. `InvidiousTVTopShelf/` is the Top Shelf extension. |
| `InvidiousMobile/` | iPhone and iPad views and touch player. `InvidiousMobileShare/` is the share extension that opens YouTube links. |

## Build

```sh
brew install xcodegen
cp Configuration/LocalSigning.xcconfig.example Configuration/LocalSigning.xcconfig  # edit values
xcodegen generate
open InvidiousTV.xcodeproj
```

Package tests run on the Mac, no simulator needed:

```sh
cd Packages/InvidiousKit && swift test
```

Schemes: `InvidiousTV` (Apple TV) and `InvidiousMobile` (iPhone and iPad). Both share the debug hooks below;
the iOS bundle ID is the tvOS one with `.mobile` appended.

## Playback

The player uses libmpv through [MPVKit](https://github.com/yattee/MPVKit) (GPL build, so the app is
GPL). It plays the best adaptive video stream the device can decode plus a separate audio stream.
On devices, mpv renders through OpenGL ES into a `CAEAGLLayer`. In the simulator, where OpenGL ES
output is unreliable, it renders through mpv's software API into a `CGImage`, so simulator playback
is capped at 720p and decoded on the CPU.

## Debug hooks (DEBUG builds only)

Environment variables let you drive the app in the simulator without the remote. With `simctl`,
prefix each with `SIMCTL_CHILD_`.

| Variable | Effect |
| --- | --- |
| `INVIDIOUS_AUTOLOGIN_USER`, `INVIDIOUS_AUTOLOGIN_PASSWORD` | Sign in and activate that profile on launch. Optional `INVIDIOUS_AUTOLOGIN_INSTANCE`. |
| `INVIDIOUS_DEBUG_TAB` | `search`, `home`, `subscriptions`, `channels`, `library` or `settings`. |
| `INVIDIOUS_DEBUG_SEARCH` | Query to prefill on the Search tab. |
| `INVIDIOUS_DEBUG_FOCUS` | `rename` or `version` to focus a Settings row. |
| `INVIDIOUS_DEBUG_COMMENTS` | Any value expands comments on video details. |
| `INVIDIOUS_DEBUG_ROUTE` | `video:<id>`, `channel:<ucid>` or `playlist:<plid>`, pushed on the Home tab. |
| `INVIDIOUS_AUTOPLAY_VIDEO` | Video ID to open directly in the player. |
| `INVIDIOUS_DEBUG_REMOTE` | Scripted remote actions for the player, e.g. `8:select,3:down,1:pan:300,1:panEnd`. Actions: `select`, `playPause`, `left`, `right`, `up`, `down`, `menu`, `pan:<points>`, `panEnd`. |

Example:

```sh
SIMCTL_CHILD_INVIDIOUS_AUTOLOGIN_USER=me SIMCTL_CHILD_INVIDIOUS_AUTOLOGIN_PASSWORD=secret \
SIMCTL_CHILD_INVIDIOUS_AUTOPLAY_VIDEO=dQw4w9WgXcQ \
xcrun simctl launch <simulator-udid> org.lobato.invidioustv
```

mpv and renderer messages go to the unified log under subsystem `org.lobato.invidioustv`:

```sh
xcrun simctl spawn <simulator-udid> log stream --level info --predicate 'subsystem == "org.lobato.invidioustv"'
```
