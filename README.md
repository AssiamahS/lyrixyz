# lyrixyz

Live synced lyrics on the Lock Screen and Dynamic Island while Spotify or Apple Music plays. Free lyric source (LRCLIB), on-device sync engine, offset slider for perfect timing.

- **Apple Music**: works out of the box (reads the system player).
- **Spotify**: paste your own client ID (developer.spotify.com → create app → redirect URI `lyrixyz://callback`), tap Connect. PKCE — no secret needed.
- **Lock Screen & Dynamic Island** toggle starts a Live Activity that follows the song line by line.

XcodeGen + CI (macos-26) → TestFlight on push.
