import Foundation
import MediaPlayer
import ActivityKit
import AVFoundation
import CryptoKit
import Observation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

/// Activity handles cross into detached tasks; ActivityKit's API is safe for this use.
final class ActivityBox: @unchecked Sendable {
    var activity: Activity<LyricsAttributes>?
}

@Observable
@MainActor
final class PlayerModel {
    enum Service: String {
        case appleMusic, spotify
    }

    var service: Service = Service(rawValue: UserDefaults.standard.string(forKey: "service") ?? "") ?? .appleMusic {
        didSet { UserDefaults.standard.set(service.rawValue, forKey: "service") }
    }
    var track = ""
    var artist = ""
    var lines: [LyricLine] = []
    var currentIndex: Int?
    var status = "Play something to start"
    var lockScreenMode = false {
        didSet { lockScreenMode ? startKeepalive() : stopKeepalive() }
    }
    var offset: Double = 0
    var spotifyClientID: String = UserDefaults.standard.string(forKey: "spotifyClientID") ?? "" {
        didSet { UserDefaults.standard.set(spotifyClientID, forKey: "spotifyClientID") }
    }
    var spotifyConnected: Bool { UserDefaults.standard.string(forKey: "spotifyRefreshToken") != nil }

    private var progress: TimeInterval = 0
    private var progressStamp = Date()
    private var isPlaying = false
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private let activityBox = ActivityBox()
    private var keepalivePlayer: AVAudioPlayer?
    private var accessToken: String?

    // MARK: lifecycle

    func start() {
        MPMediaLibrary.requestAuthorization { _ in }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled {
                self.tick()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    // MARK: now playing

    private func poll() async {
        switch service {
        case .appleMusic: pollAppleMusic()
        case .spotify: await pollSpotify()
        }
    }

    private func pollAppleMusic() {
        let player = MPMusicPlayerController.systemMusicPlayer
        guard let item = player.nowPlayingItem else {
            status = "Nothing playing in Apple Music"
            return
        }
        isPlaying = player.playbackState == .playing
        progress = player.currentPlaybackTime
        progressStamp = Date()
        let title = item.title ?? ""
        let by = item.artist ?? ""
        if title != track || by != artist {
            trackChanged(title: title, artist: by)
        }
    }

    private func pollSpotify() async {
        guard let token = await validSpotifyToken() else {
            status = spotifyClientID.isEmpty
                ? "Paste your Spotify client ID in Settings"
                : "Connect Spotify in Settings"
            return
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = json["item"] as? [String: Any] else {
            status = "Nothing playing on Spotify"
            return
        }
        isPlaying = json["is_playing"] as? Bool ?? false
        progress = Double(json["progress_ms"] as? Int ?? 0) / 1000
        progressStamp = Date()
        let title = item["name"] as? String ?? ""
        let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let by = artists.joined(separator: ", ")
        if title != track || by != artist {
            trackChanged(title: title, artist: by)
        }
    }

    private func trackChanged(title: String, artist by: String) {
        track = title
        artist = by
        lines = []
        currentIndex = nil
        status = "Fetching lyrics…"
        Task { await self.fetchLyrics() }
    }

    // MARK: lyrics (LRCLIB, free + keyless)

    private func fetchLyrics() async {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: track),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let synced = json["syncedLyrics"] as? String, !synced.isEmpty else {
            status = "No synced lyrics for this one"
            return
        }
        lines = Self.parseLRC(synced)
        status = lines.isEmpty ? "No synced lyrics for this one" : ""
    }

    static func parseLRC(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for rawLine in lrc.split(separator: "\n") {
            let line = String(rawLine)
            guard let close = line.firstIndex(of: "]"), line.hasPrefix("[") else { continue }
            let stamp = String(line[line.index(after: line.startIndex)..<close])
            let text = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { continue }
            guard !text.isEmpty else { continue }
            result.append(LyricLine(time: minutes * 60 + seconds, text: text))
        }
        return result.sorted { $0.time < $1.time }
    }

    // MARK: sync tick

    private func tick() {
        guard !lines.isEmpty else {
            endActivityIfIdle()
            return
        }
        let now = isPlaying ? progress + Date().timeIntervalSince(progressStamp) + offset : progress + offset
        let index = lines.lastIndex { $0.time <= now }
        if index != currentIndex {
            currentIndex = index
            updateActivity()
        }
    }

    var currentLine: String {
        guard let currentIndex, lines.indices.contains(currentIndex) else { return "♪" }
        return lines[currentIndex].text
    }

    var nextLine: String {
        guard let currentIndex, lines.indices.contains(currentIndex + 1) else { return "" }
        return lines[currentIndex + 1].text
    }

    // MARK: live activity

    private func updateActivity() {
        guard lockScreenMode else { return }
        let state = LyricsAttributes.ContentState(
            line: currentLine, nextLine: nextLine, track: track, artist: artist)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
        let attributes = LyricsAttributes(service: service.rawValue)
        let box = activityBox
        Task.detached {
            if let activity = box.activity {
                await activity.update(content)
            } else {
                box.activity = try? Activity.request(attributes: attributes, content: content)
            }
        }
    }

    private func endActivityIfIdle() {
        guard lines.isEmpty, activityBox.activity != nil else { return }
        endActivity()
    }

    private func endActivity() {
        let box = activityBox
        Task.detached {
            if let running = box.activity {
                box.activity = nil
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: keepalive (lets the activity keep updating with the screen locked)

    private func startKeepalive() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        keepalivePlayer = try? AVAudioPlayer(contentsOf: url)
        keepalivePlayer?.numberOfLoops = -1
        keepalivePlayer?.volume = 0
        keepalivePlayer?.play()
        updateActivity()
    }

    private func stopKeepalive() {
        keepalivePlayer?.stop()
        keepalivePlayer = nil
        endActivity()
    }

    // MARK: spotify auth (PKCE — client id only, no secret)

    private(set) var pendingVerifier: String?

    func spotifyAuthURL() -> URL? {
        guard !spotifyClientID.isEmpty else { return nil }
        let verifier = Self.randomVerifier()
        pendingVerifier = verifier
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: spotifyClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "lyrixyz://callback"),
            URLQueryItem(name: "scope", value: "user-read-currently-playing user-read-playback-state"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        return comps.url
    }

    func handleSpotifyCallback(_ url: URL) async {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value,
            let verifier = pendingVerifier else { return }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=lyrixyz://callback",
            "client_id=\(spotifyClientID)",
            "code_verifier=\(verifier)",
        ].joined(separator: "&").data(using: .utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            status = "Spotify sign-in failed"
            return
        }
        accessToken = token
        if let refresh = json["refresh_token"] as? String {
            UserDefaults.standard.set(refresh, forKey: "spotifyRefreshToken")
        }
        UserDefaults.standard.set(Date().addingTimeInterval(3000), forKey: "spotifyTokenExpiry")
        status = "Spotify connected"
    }

    private func validSpotifyToken() async -> String? {
        if let accessToken,
           let expiry = UserDefaults.standard.object(forKey: "spotifyTokenExpiry") as? Date,
           expiry > Date() {
            return accessToken
        }
        guard let refresh = UserDefaults.standard.string(forKey: "spotifyRefreshToken"),
              !spotifyClientID.isEmpty else { return nil }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "grant_type=refresh_token",
            "refresh_token=\(refresh)",
            "client_id=\(spotifyClientID)",
        ].joined(separator: "&").data(using: .utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else { return nil }
        accessToken = token
        if let newRefresh = json["refresh_token"] as? String {
            UserDefaults.standard.set(newRefresh, forKey: "spotifyRefreshToken")
        }
        UserDefaults.standard.set(Date().addingTimeInterval(3000), forKey: "spotifyTokenExpiry")
        return token
    }

    private static func randomVerifier() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<64).compactMap { _ in chars.randomElement() })
    }
}
