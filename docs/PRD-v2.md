# Invidious TV — v2 scope

Status: complete and checked on real devices, 2026-09-04 (v1.0), except livestreams (see 7)
Builds on `PRD-v1.md`. Same architecture; features land one at a time on `main`.

## Order of work

1. **Search** (done): Search tab with live suggestions, channel shelf and video grid, paging. Pasting a
   YouTube, youtu.be, Shorts, live, channel or Invidious link, or a bare video ID, opens the target.
2. **Autoplay next** (done): when a video ends, a countdown offers the next recommended video; Cancel returns
   to details, Play Now starts immediately. Setting to turn autoplay off.
3. **Playlists and Watch Later** (done): Library tab listing the account's playlists; playlist page with videos;
   "Save to Watch Later" and "Save to playlist" on video details.
4. **Comments** (done): top-level comments on the video details page, loaded on demand.
5. **SponsorBlock** (done): skip sponsor and self-promotion segments during playback with an on-screen notice;
   categories configurable in Settings. DeArrow is out of scope for now.
6. **Top Shelf** (done): Continue Watching and latest subscriptions on the tvOS home screen via a Top Shelf
   extension sharing data through an app group.
7. **Livestreams** (blocked by the instance): re-investigated with a currently live video on
   2026-09-04. The instance runs invidious-companion. For live videos the API returns no `hlsUrl`,
   `/api/manifest/dash/id/:id` redirects to companion and returns a manifest with no usable
   representations, and the adaptive format URLs are segmented live endpoints that mpv cannot
   play directly. The earlier `hls_variant` attempt returned an empty body. Live playback needs
   either an Invidious/companion fix or a YouTube HLS manifest fetched by other means, so it stays
   out until then.
8. **Hide Shorts** (done, off by default): videos of 60 seconds or less and titles tagged #shorts.
   No further work planned (see scoped out).
9. **iCloud sync of resume positions** (done, on by default): positions sync across the user's devices through the iCloud
   key-value store. Buckets are keyed by instance and username, so a profile for the same account on
   another device picks them up regardless of the local profile ID. Newest `updatedAt` wins per video;
   finished videos are kept as tombstones so they stay finished everywhere. Setting to turn it off.
10. **QR-code login from a phone** (done, tvOS): the login screen offers "Sign in with your phone". The TV
    shows a QR code for the instance's `/authorize_token` page with a callback to a small HTTP listener
    on the TV. The phone signs in to Invidious in its browser, approves, and the browser is redirected
    to the TV with the token and username. The app then uses `Authorization: Bearer` for that profile.
    Scopes requested: `:feed`, `:subscriptions*`, `:history*`, `:playlists*`, `POST:tokens/unregister`
    (so removing the profile revokes its own token). Phone and TV must be on the same network.

## Added along the way (2026-09-04)

- Watch history: the account's history as a list (iOS, from the profile menu and Library, with swipe-to-remove) or a
  grid (tvOS, from Library), paged, with Clear History. Invidious returns only IDs, so pages are resolved to video
  summaries a few at a time and resume snapshots are reused.
- Channel name filter on the Channels tab.
- Top Shelf refreshes its uploads in the background: the extension fetches the feed itself with the profile's credential
  from a shared keychain group when the app's snapshot is older than 15 minutes.
- Original-language audio by default and an Audio menu for dubs; tappable description links; profile menu on iOS.

## Scoped out

- DeArrow.
- Hide Shorts improvements (channel shorts-tab cache).

## v3

- macOS app on top of `InvidiousKit`.

## iOS (done on the simulator, 2026-09-04)

iPhone and iPad app (`InvidiousMobile`) on the same `InvidiousKit`, app model, stores and view models as
tvOS. Tabs: Home, Subscriptions, Channels, Library, Settings and a Search tab. Touch player on MPV with
tap-to-show controls, slider scrubbing, speed, captions, quality, autoplay and playlist queues. Share
extension (`InvidiousMobileShare`) accepts YouTube links from any app and opens the video; if the
extension cannot open the app directly, the link waits in the app group and opens on next activation.
Paste-a-link in search works as on tvOS. AVKit was not used because the instance returns no muxed
progressive streams, so MPV is required for any playback.
