# Invidious TV — v2 scope

Status: in progress, started 2026-09-04
Builds on `PRD-v1.md`. Same architecture; features land one at a time on `main`.

## Order of work

1. **Search** (done): Search tab with live suggestions, channel shelf and video grid, paging. Pasting a
   YouTube, youtu.be, Shorts, live, channel or Invidious link, or a bare video ID, opens the target.
2. **Autoplay next**: when a video ends, a countdown offers the next recommended video; Cancel returns
   to details, Play Now starts immediately. Setting to turn autoplay off.
3. **Playlists and Watch Later**: Library tab listing the account's playlists; playlist page with videos;
   "Save to Watch Later" and "Save to playlist" on video details.
4. **Comments**: top-level comments on the video details page, loaded on demand.
5. **SponsorBlock**: skip sponsor and self-promotion segments during playback with an on-screen notice;
   categories configurable in Settings. DeArrow is out of scope for now.
6. **Top Shelf**: Continue Watching and latest subscriptions on the tvOS home screen via a Top Shelf
   extension sharing data through an app group.
7. **Livestreams**: re-investigate HLS through the instance with a currently live video; fall back to
   DASH live if needed.
8. **Hide Shorts** (off by default): duration heuristic plus channel shorts-tab cache.

Deferred beyond v2: iCloud sync of resume positions, QR-code login.

## iOS (after v2)

iPhone and iPad app on the same `InvidiousKit` and feature code where SwiftUI allows, with an AVKit or
MPV player, a share extension that accepts YouTube links and opens the video, and paste-a-link in search.
