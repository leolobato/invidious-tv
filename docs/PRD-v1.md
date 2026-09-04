# Invidious TV — PRD v1

Status: v1 complete; acceptance checklist run on a real Apple TV and iPhone on 2026-09-04 (v1.0)
Date: 2026-09-03
Bundle ID: configured per build in `Configuration/LocalSigning.xcconfig` (`APP_BUNDLE_ID`)
Platform: tvOS 26 (iOS and macOS in later versions)

## 1. Summary

A tvOS app for watching YouTube through a self-hosted Invidious instance. The UX follows the
official YouTube TV app: a profile picker, a home screen with personalized recommendations,
a chronological subscriptions feed, a channel browser, and a full-screen player with scrubbing.

The API client, models, and persistence live in a platform-agnostic Swift package so the same
core can back iOS and macOS apps later.

Yattee (`../yattee`) is a reference only. Its UX is not reused. Its playback stack (MPVKit) is
reused as the starting point for the player.

## 2. Goals

- Watch subscribed channels in chronological order, in a thumbnail grid.
- Get YouTube-like recommendations on the home screen despite Invidious having no home feed.
- Play at the best quality the instance offers (DASH, up to 4K).
- Resume unfinished videos.
- Support several household members, each with their own Invidious account.

## 3. Non-goals for v1

Deferred to v2 (section 12): livestreams, search UI, shorts filtering, playlists and Watch Later,
autoplay, Top Shelf, SponsorBlock, DeArrow, comments, iCloud sync, QR-code login, iOS and macOS
targets.

## 4. Target instance and API facts

- Development instance: `http://192.168.1.10:3000`, Invidious `2026.08.04`. Plain HTTP on LAN.
- Authentication: `POST /login` (form fields `email`, `password`, `action=signin`) returns a
  `SID` cookie valid for 2 years. All `/api/v1/auth/*` endpoints accept it as
  `Cookie: SID=<value>`. No browser step required.
- Endpoints used in v1:

| Purpose | Endpoint |
| --- | --- |
| Login | `POST /login` |
| Subscriptions feed (chronological, paginated) | `GET /api/v1/auth/feed?page=N&max_results=M` |
| Subscribed channels | `GET /api/v1/auth/subscriptions` |
| Watch history (video IDs, newest first) | `GET /api/v1/auth/history?page=N` |
| Mark watched | `POST /api/v1/auth/history/:id` |
| Video details, streams, recommendations | `GET /api/v1/videos/:id` |
| Channel info | `GET /api/v1/channels/:ucid` |
| Channel videos (continuation-based) | `GET /api/v1/channels/:ucid/videos?continuation=` |
| Trending (fallback for Home) | `GET /api/v1/trending` |
| Proxied stream URLs | `GET /api/v1/videos/:id?local=true` |
| Captions | `GET /api/v1/captions/:id?label=` |
| Storyboards (seek previews) | `GET /api/v1/storyboards/:id` |

Known API limitations that shape the design:

- No personalized feed. Home is synthesized client-side (section 6.2).
- No shorts flag on feed or video objects. Shorts filtering is out of scope.
- History stores video IDs only, not positions. Resume positions are stored locally.

## 5. Users and profiles

- A profile is one Invidious account (email + password) on one instance.
- On launch the app shows a profile picker (like YouTube TV / Netflix). The last used profile
  is preselected and can be chosen with a single click.
- Profiles can be added, renamed, and removed in Settings. Removing a profile deletes its
  session and local data (resume positions, home cache).
- Credentials are never stored. Only the `SID` session is stored, in the Keychain, keyed by
  profile ID. When a request returns 401 or 403 the profile is marked as needing re-login.
- All per-user state (session, resume positions, caches) is namespaced by profile ID.

## 6. Screens

Navigation is a tvOS tab bar: **Home**, **Subscriptions**, **Channels**, **Settings**.
Selecting a video anywhere opens the Video Details screen. Playing opens the Player.

### 6.1 Profile picker

- Full-screen grid of profile avatars (initials on a colored circle) plus an "Add profile" tile.
- Selecting a profile loads the session and enters the tab bar.
- If no profile exists, the picker opens the Login screen directly.

### 6.2 Home

Sections, top to bottom, each a horizontal shelf:

1. **Continue watching**: videos with a saved resume position between 5% and 95%, most
   recent first. Hidden when empty.
2. **Recommended**: synthesized as follows.
   - Take the 10 most recent IDs from `/api/v1/auth/history`.
   - Fetch `/api/v1/videos/:id` for each (concurrently, cached) and collect
     `recommendedVideos`.
   - Drop duplicates and anything present in the user's history.
   - Interleave results round-robin across the seed videos so one seed does not dominate.
   - Cache the result per profile for 30 minutes. Refresh on pull, on app foreground after
     the cache expires, and after a video finishes.
   - If history is empty, or the result has fewer than 12 items, pad with `/api/v1/trending`.
3. **Latest from subscriptions**: first page of the subscriptions feed, as a teaser.

### 6.3 Subscriptions

- Grid of video cards from `/api/v1/auth/feed`, newest first. Infinite scroll by page.
- Grid uses 4 columns at 1080p (thumbnail 16:9 with duration badge, title on two lines,
  channel name and relative date on one line).
- Cards show a thin progress bar when a resume position exists and a "watched" dim state
  when the video ID is in the account's history.

### 6.4 Channels

- Grid of all subscribed channels from `/api/v1/auth/subscriptions`, sorted alphabetically.
  Each tile shows avatar and name. Avatars come from `/api/v1/channels/:ucid` lazily.
- Selecting a channel opens Channel Details.

### 6.5 Channel details

- Header: banner, avatar, name, subscriber count, short description.
- Grid of the channel's videos, newest first, loaded with continuation tokens.
- Subscribe and unsubscribe button using `/api/v1/auth/subscriptions/:ucid`.

### 6.6 Video details

- Large thumbnail with a **Play** (or **Resume from mm:ss**) button focused by default.
- Title, channel (avatar + name, selectable to open Channel Details), view count, like
  count, publish date.
- Description, collapsed to 3 lines with a "More" action that expands it in place.
- **Up next** shelf using `recommendedVideos` from the same response.

### 6.7 Player

- Full-screen, custom controls (MPV has no system player UI).
- Starts at the best available quality. The player loads the highest adaptive video stream
  the device can decode plus the best audio stream as a separate track, rather than the DASH
  manifest, which gives exact control over quality. With `local=true` the streams are proxied
  by the instance (works even when googlevideo URLs are region or IP locked). A setting can
  turn proxying off.
- Controls, shown on any remote interaction and auto-hidden after 4 seconds:
  - Play / pause (click on the touch surface or play/pause button).
  - Scrubbing: swipe left/right on the touch surface moves a scrubber along the progress bar
    with a storyboard preview thumbnail and time; click to seek. Left/right press skips
    10 seconds.
  - Title and channel overlay at the top.
  - An options row (menu button or swipe down): playback speed (0.75–2.0), captions
    (off or one of the available tracks), quality override (auto or a fixed height).
- Pressing Menu exits to Video Details and saves the position.
- When the video ends, the app returns to Video Details with **Up next** focused.
  Autoplay is out of scope for v1.
- Livestreams (`liveNow` true) are not playable in v1. The Video Details screen says so and
  disables Play. The instance's `hls_variant` manifest endpoint answered with a redirect during
  development, so live playback needs its own investigation (v2).

### 6.8 Settings

- Instance URL (default `http://192.168.1.10:3000`), validated by calling `/api/v1/stats`.
- Profiles: list, add, rename, remove, re-login.
- Playback: proxy media through instance (default on), maximum quality (default unlimited),
  default speed (default 1.0).
- About: app version, instance version.

### 6.9 Login

- Username and password fields with the tvOS keyboard, plus instance URL if not yet set.
- On success, the app creates the profile (display name defaults to the username) and
  returns to the profile picker.
- QR-code login from a phone is a v2 fallback and is not needed while the form works.

## 7. Resume and watch history

- Position is saved locally every 5 seconds during playback, on pause, on exit, and on
  background. Record: `videoId`, `position`, `duration`, `updatedAt`, `profileId`.
- A video is considered finished at 95% or more. Finished videos are removed from
  Continue watching.
- On play start the app calls `POST /api/v1/auth/history/:id` so the account history
  (which also feeds Home recommendations) stays in sync with the web UI.
- Storage: one JSON file in Application Support, entries namespaced by profile ID.

## 8. Architecture

```
invidious-app/
  project.yml                  XcodeGen spec
  Configuration/
    Base.xcconfig              committed: default signing, includes LocalSigning if present
    LocalSigning.xcconfig      gitignored: DEVELOPMENT_TEAM and APP_BUNDLE_ID override
    LocalSigning.xcconfig.example  committed template
  Packages/InvidiousKit/       Swift package, no UI, platforms: tvOS 26, iOS 26, macOS 26
    Sources/InvidiousKit/
      API/                     InvidiousClient (URLSession, async/await), endpoint definitions
      Models/                  Codable models: Video, VideoDetails, Channel, FeedPage, ...
      Auth/                    LoginService, SessionStore (Keychain)
      Profiles/                ProfileStore
      Home/                    HomeFeedBuilder (pure function, unit-tested)
      Persistence/             ResumeStore (JSON file, per profile)
    Tests/InvidiousKitTests/   JSON fixtures recorded from the real instance
  InvidiousTV/                 tvOS app target (SwiftUI)
    App/                       entry point, root navigation, dependency container
    Features/                  ProfilePicker, Home, Subscriptions, Channels, VideoDetails,
                               Player, Settings, Login
    Player/                    MPV integration adapted from Yattee (backend + render view)
    Shared/                    VideoCard, ChannelTile, Shelf, focus helpers, formatting
```

- **UI**: SwiftUI only, tvOS 26 APIs, no availability fallbacks.
- **Concurrency**: Swift 6 strict concurrency, async/await, `@Observable` view models.
- **Images**: Nuke + NukeUI for the grids (disk cache, prefetching, downsampling).
- **Player**: MPVKit, `https://github.com/yattee/MPVKit.git` exact `1.0.1` (GPL build).
  The app is therefore GPL-licensed. A small libmpv wrapper (`MPVPlayer`) plus two render
  views: OpenGL ES into a `CAEAGLLayer` on devices, and mpv's software render API into a
  `CGImage` in the simulator, where OpenGL ES output is garbled. Yattee's render code served
  as the reference for both paths.
- **Dependencies**: MPVKit and Nuke only.
- **Testing**: `InvidiousKit` tests run with `swift test` on the Mac host (no simulator).
  Recorded fixtures cover decoding of every endpoint used, the home feed builder, session
  handling, and the resume store. UI is verified on the tvOS simulator through DEBUG-only
  environment hooks (auto-login, start tab or route, autoplay, scripted remote actions; see
  README) and on a real Apple TV.

## 9. Error handling

- Instance unreachable: full-screen retry state on the current tab with the error message.
- Session expired (401/403): banner on the profile tile and an inline re-login prompt.
- Video unavailable or stream extraction failed: alert on Video Details with retry.
- Playback errors from MPV: overlay with the message and a retry that reloads the manifest.
- All network calls time out at 15 seconds; media requests follow MPV's own timeouts.

## 10. Performance targets

- Cold launch to profile picker under 1 second.
- Subscriptions first page rendered under 1.5 seconds on LAN.
- Grid scrolling at 60 fps with thumbnails prefetched one row ahead.
- Playback starts within 3 seconds of pressing Play on LAN.

## 11. Acceptance criteria

1. Two profiles can log in with username and password and switch from the picker without
   re-entering credentials after relaunch.
2. Subscriptions shows the same videos in the same order as the instance's web feed.
3. Channels lists every subscribed channel; opening one shows its videos and can page further.
4. Home shows Continue watching when applicable and at least 12 recommended videos for an
   account with history.
5. A 4K video plays at 2160p by default on a 4K Apple TV. The stats overlay in the options
   row shows the active resolution.
6. Play, pause, ±10 s skip, and scrubbing with preview thumbnails work with the Siri Remote.
7. Exiting a video at 40% and reopening it offers Resume at the same position, and the video
   appears in Continue watching.
8. Playing a video marks it watched on the instance (visible in the web UI history).
9. Changing the instance URL to an invalid host produces a clear error and does not break
   existing profiles.
10. `swift test` passes for `InvidiousKit`.

## 12. v2 backlog

- Livestream playback (HLS through the instance or DASH live), with live chat later.
- Search with suggestions (`/api/v1/search`, `/api/v1/search/suggestions`).
- Hide shorts (duration heuristic plus channel shorts-tab cache).
- Playlists and Watch Later (`/api/v1/auth/playlists`).
- Autoplay next with a countdown, and a play queue.
- Top Shelf extension with Continue watching and latest subscriptions.
- SponsorBlock and DeArrow.
- Comments.
- iCloud sync of resume positions across devices.
- QR-code login from a phone.
- iOS and macOS apps on top of `InvidiousKit`.

## 13. Milestones

1. **Skeleton**: XcodeGen project, xcconfig signing, `InvidiousKit` with client, models, login,
   profile picker, and Settings with instance URL. Builds and logs in on the simulator.
2. **Browse**: Subscriptions grid, Channels grid, Channel Details, Video Details.
3. **Play**: MPVKit integration, custom controls, scrubbing, quality, captions, speed.
4. **Resume and Home**: ResumeStore, Continue watching, synthesized recommendations, history sync.
5. **Polish**: error states, focus tuning, performance pass, acceptance run on real Apple TV.
