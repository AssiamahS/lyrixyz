import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @State private var model = PlayerModel()
    @Environment(\.webAuthenticationSession) private var webAuth

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.02, blue: 0.05), .black],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 24) {
                    header
                    Spacer()
                    lyricsPane
                    Spacer()
                    controls
                }
                .padding()
            }
            .navigationTitle("lyrixyz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .onOpenURL { url in
            Task { await model.handleSpotifyCallback(url) }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(model.track.isEmpty ? "—" : model.track)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(model.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var lyricsPane: some View {
        VStack(spacing: 18) {
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(model.currentLine)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: model.currentLine)
            Text(model.nextLine)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Picker("Service", selection: $model.service) {
                Text("Apple Music").tag(PlayerModel.Service.appleMusic)
                Text("Spotify").tag(PlayerModel.Service.spotify)
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $model.lockScreenMode) {
                Label("Lock Screen & Dynamic Island", systemImage: "platter.filled.top.iphone")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.pink)

            if model.service == .spotify {
                spotifyControls
            }

            HStack {
                Text("Offset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $model.offset, in: -5...5, step: 0.5)
                Text(String(format: "%+.1fs", model.offset))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var spotifyControls: some View {
        VStack(spacing: 10) {
            if !model.spotifyConnected {
                TextField("Spotify client ID (developer.spotify.com)", text: $model.spotifyClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
                    .padding(10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Button {
                    connectSpotify()
                } label: {
                    Label("Connect Spotify", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.spotifyClientID.isEmpty)
            } else {
                Label("Spotify connected", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func connectSpotify() {
        guard let url = model.spotifyAuthURL() else { return }
        Task {
            if let callback = try? await webAuth.authenticate(
                using: url, callbackURLScheme: "lyrixyz") {
                await model.handleSpotifyCallback(callback)
            }
        }
    }
}
