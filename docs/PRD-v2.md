# Invidious TV — v2 scope

Status: complete on the tvOS simulator, 2026-09-04, except livestreams (see 7)
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
   The channel shorts-tab cache was not needed for a first version.

Deferred beyond v2: iCloud sync of resume positions, QR-code login.

## iOS (after v2)

iPhone and iPad app on the same `InvidiousKit` and feature code where SwiftUI allows, with an AVKit or
MPV player, a share extension that accepts YouTube links and opens the video, and paste-a-link in search.
