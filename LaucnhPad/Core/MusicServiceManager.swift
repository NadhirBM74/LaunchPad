import Foundation
import Combine
import SwiftUI
import AppKit
import MusicKit
import AuthenticationServices
import CryptoKit
import Security

// MARK: - Modèles de données des services musicaux

public enum MusicServiceSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMusic
    case spotify
    case system
    case none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleMusic: return loc("music.apple.title")
        case .spotify: return loc("music.spotify.title")
        case .system: return loc("music.service.auto")
        case .none: return loc("music.status.not_connected")
        }
    }
}

public enum MusicServiceStatus: Equatable, Sendable {
    case notConnected
    case connecting
    case connected(details: String?)
    case restricted(reason: String)
    case error(message: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .connected: return loc("music.status.connected")
        case .connecting: return loc("music.status.connecting")
        case .notConnected: return loc("music.status.not_connected")
        case .restricted: return loc("music.status.restricted")
        case .error: return loc("music.status.error")
        }
    }
}

public struct NowPlayingTrack: Equatable, @unchecked Sendable {
    nonisolated(unsafe) private static let sharedImageCache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 48
        return cache
    }()

    private static func cachedImage(for data: Data?) -> NSImage? {
        guard let data, !data.isEmpty else { return nil }
        var hasher = Hasher()
        hasher.combine(data.count)
        if data.count <= 256 {
            hasher.combine(data)
        } else {
            hasher.combine(data.prefix(128))
            hasher.combine(data.suffix(128))
        }
        let key = NSNumber(value: hasher.finalize())
        if let existing = sharedImageCache.object(forKey: key) {
            return existing
        }
        guard let decoded = NSImage(data: data) else { return nil }
        sharedImageCache.setObject(decoded, forKey: key)
        return decoded
    }

    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var artworkData: Data? {
        didSet {
            if artworkData != oldValue {
                _cachedImage = Self.cachedImage(for: artworkData)
            }
        }
    }
    public var isPlaying: Bool
    public var elapsedSeconds: Double
    public var durationSeconds: Double
    public var serviceSource: MusicServiceSource
    public var canControlPlayback: Bool
    public var limitationNotice: String?
    /// Application qui publie la lecture (renseigné pour la source système : navigateur, VLC, lecteur vidéo…).
    public var sourceBundleID: String = ""
    public var sourceAppName: String = ""

    private var _cachedImage: NSImage?

    public init(
        title: String,
        artist: String,
        album: String,
        artworkURL: URL?,
        artworkData: Data?,
        isPlaying: Bool,
        elapsedSeconds: Double,
        durationSeconds: Double,
        serviceSource: MusicServiceSource,
        canControlPlayback: Bool,
        limitationNotice: String?
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.artworkData = artworkData
        self.isPlaying = isPlaying
        self.elapsedSeconds = elapsedSeconds
        self.durationSeconds = durationSeconds
        self.serviceSource = serviceSource
        self.canControlPlayback = canControlPlayback
        self.limitationNotice = limitationNotice
        self._cachedImage = Self.cachedImage(for: artworkData)
    }

    public static func == (lhs: NowPlayingTrack, rhs: NowPlayingTrack) -> Bool {
        let sameArtwork: Bool
        if let lImg = lhs._cachedImage, let rImg = rhs._cachedImage, lImg === rImg {
            sameArtwork = true
        } else {
            sameArtwork = (lhs.artworkData?.count == rhs.artworkData?.count) && (lhs.artworkData == rhs.artworkData)
        }
        return lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.artworkURL == rhs.artworkURL &&
        sameArtwork &&
        lhs.isPlaying == rhs.isPlaying &&
        Int(lhs.elapsedSeconds.rounded()) == Int(rhs.elapsedSeconds.rounded()) &&
        Int(lhs.durationSeconds.rounded()) == Int(rhs.durationSeconds.rounded()) &&
        lhs.serviceSource == rhs.serviceSource &&
        lhs.canControlPlayback == rhs.canControlPlayback &&
        lhs.limitationNotice == rhs.limitationNotice &&
        lhs.sourceBundleID == rhs.sourceBundleID &&
        lhs.sourceAppName == rhs.sourceAppName
    }

    public static let empty = NowPlayingTrack(
        title: "",
        artist: "",
        album: "",
        artworkURL: nil,
        artworkData: nil,
        isPlaying: false,
        elapsedSeconds: 0,
        durationSeconds: 0,
        serviceSource: .none,
        canControlPlayback: true,
        limitationNotice: nil
    )

    public var hasTrack: Bool {
        !title.isEmpty || !artist.isEmpty
    }

    public var artworkImage: NSImage? {
        if let _cachedImage { return _cachedImage }
        return Self.cachedImage(for: artworkData)
    }

    /// Miniature à afficher : pochette/miniature publiée, sinon icône de l'application source.
    @MainActor
    public var displayImage: NSImage? {
        artworkImage ?? SystemNowPlayingClient.appIcon(bundleID: sourceBundleID)
    }
}

// MARK: - Sécurisation des jetons (Keychain macOS natif)

enum KeychainHelper {
    static let serviceName = "me.LaucnhPad.music"

    @discardableResult
    static func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func saveString(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Contexte de présentation WebAuth pour macOS

final class WebAuthPresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSWindow()
    }
}

// MARK: - Gestionnaire central des services musicaux

@MainActor
public final class MusicServiceManager: ObservableObject {
    public static let shared = MusicServiceManager()

    // Configuration Spotify
    public static let spotifyRedirectURI = "launchpad://spotify-callback"
    // Client ID par défaut (remplaçable dans les Paramètres pour le mode développeur)
    public static let defaultSpotifyClientID = "a1b2c3d4e5f6478980b1c2d3e4f5a6b7"

    // États publiés
    @Published public private(set) var appleMusicStatus: MusicServiceStatus = .notConnected
    @Published public private(set) var appleMusicCanPlayCatalog: Bool = false
    @Published public private(set) var appleMusicSubscriptionDescription: String = ""

    @Published public private(set) var spotifyStatus: MusicServiceStatus = .notConnected
    @Published public private(set) var spotifyUserDisplayName: String? = nil
    @Published public private(set) var spotifyProductType: String? = nil // "premium", "free", etc.
    @Published public private(set) var spotifyLimitationNotice: String? = nil

    @Published public var preferredService: MusicServiceSource = .system {
        didSet {
            UserDefaults.standard.set(preferredService.rawValue, forKey: "PreferredMusicService")
            guard preferredService != oldValue else { return }
            refreshNowPlaying()
        }
    }

    @Published public var customSpotifyClientID: String = "" {
        didSet {
            UserDefaults.standard.set(customSpotifyClientID, forKey: "SpotifyCustomClientID")
        }
    }

    @Published public private(set) var currentTrack: NowPlayingTrack = .empty
    @Published public private(set) var isLaunchingRandomTrack: Bool = false
    @Published public var isMuted: Bool = false

    // Feedback pour l'UI
    @Published public var alertMessage: String? = nil

    // Objets privés
    private let authAnchorProvider = WebAuthPresentationAnchorProvider()
    private var pendingPKCEVerifier: String?
    private var pendingAuthState: String?
    private var authSession: ASWebAuthenticationSession?
    private var timer: Timer?
    private var progressTimer: Timer?
    private var lastProgressTickUptime: TimeInterval = 0
    private var artworkCache: [String: Data] = [:]
    private var inFlightArtworkQueries: Set<String> = []
    private var isRefreshingNowPlaying = false
    private var lastRefreshUptime: TimeInterval = 0
    private var lastSystemFetchUptime: TimeInterval = 0
    private var cachedSystemTrack: NowPlayingTrack? = nil

    private init() {
        let savedPref = UserDefaults.standard.string(forKey: "PreferredMusicService")
            .flatMap { MusicServiceSource(rawValue: $0) } ?? .system
        self._preferredService = Published(initialValue: savedPref)

        let savedClientID = UserDefaults.standard.string(forKey: "SpotifyCustomClientID") ?? ""
        self._customSpotifyClientID = Published(initialValue: savedClientID)

        setupDistributedNotifications()

        // Toutes les vérifications asynchrones et l'actualisation initiale sont différées
        // sur la prochaine boucle MainActor, après le retour complet de init() et la fin du dispatch_once.
        Task { @MainActor [weak self] in
            guard let self else { return }

            if UserDefaults.standard.bool(forKey: "AppleMusicConnected") {
                self.verifyAppleMusicAuthorization()
            }

            if KeychainHelper.loadString(key: "spotify_access_token") != nil {
                self.spotifyStatus = .connected(details: UserDefaults.standard.string(forKey: "SpotifyUserDisplayName"))
                self.verifySpotifyConnection()
            }

            if LaunchpadViewModel.isLaunchpadVisible {
                self.refreshNowPlaying(force: true)
                self.startPolling()
            }
        }
    }

    public var effectiveSpotifyClientID: String {
        let trimmed = customSpotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultSpotifyClientID : trimmed
    }

    // MARK: - Initialisation & Notifications Système (macOS)

    private func setupDistributedNotifications() {
        let dnc = DistributedNotificationCenter.default()
        // Changement de morceau dans l'application Musique macOS
        dnc.addObserver(
            self,
            selector: #selector(handleAppleMusicNotification(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        // Changement de morceau dans l'application Spotify macOS
        dnc.addObserver(
            self,
            selector: #selector(handleSpotifyNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        // Visibilité du Launchpad pour suspendre/reprendre les tâches
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLaunchpadVisibilityChanged(_:)),
            name: .launchpadVisibilityDidChange,
            object: nil
        )
    }

    @objc private func handleLaunchpadVisibilityChanged(_ notif: Notification) {
        let isVisible = (notif.object as? Bool) ?? false
        Task { @MainActor [weak self] in
            guard let self else { return }
            if isVisible {
                self.refreshNowPlaying(force: true)
                self.startPolling()
            } else {
                self.stopPolling()
            }
        }
    }

    @objc private func handleAppleMusicNotification(_ notif: Notification) {
        guard let info = notif.userInfo else { return }
        Task { @MainActor [weak self] in
            self?.processAppleMusicNotification(info: info)
        }
    }

    private func processAppleMusicNotification(info: [AnyHashable: Any]) {
        let playerState = (info["Player State"] as? String) ?? ""
        let isPlaying = playerState.lowercased() == "playing"
        let name = (info["Name"] as? String) ?? ""
        let artist = (info["Artist"] as? String) ?? ""
        let album = (info["Album"] as? String) ?? ""
        let totalTimeSec = ((info["Total Time"] as? NSNumber)?.doubleValue ?? 0) / 1000.0

        if !name.isEmpty {
            let isSameSong = (self.currentTrack.title == name && self.currentTrack.artist == artist)
            let cacheKey = artworkCacheKey(title: name, artist: artist)
            let existingArtwork = isSameSong ? self.currentTrack.artworkData : artworkCache[cacheKey]

            self.currentTrack = NowPlayingTrack(
                title: name,
                artist: artist,
                album: album,
                artworkURL: nil,
                artworkData: existingArtwork,
                isPlaying: isPlaying,
                elapsedSeconds: isSameSong ? self.currentTrack.elapsedSeconds : 0,
                durationSeconds: totalTimeSec > 0 ? totalTimeSec : (isSameSong ? self.currentTrack.durationSeconds : 240),
                serviceSource: .appleMusic,
                canControlPlayback: true,
                limitationNotice: nil
            )

            if existingArtwork == nil, LaunchpadViewModel.isLaunchpadVisible {
                resolveArtwork(for: name, artist: artist, album: album)
            }
        }
    }

    @objc private func handleSpotifyNotification(_ notif: Notification) {
        guard let info = notif.userInfo else { return }
        Task { @MainActor [weak self] in
            self?.processSpotifyNotification(info: info)
        }
    }

    private func processSpotifyNotification(info: [AnyHashable: Any]) {
        let playerState = (info["Player State"] as? String) ?? ""
        let isPlaying = playerState.lowercased() == "playing"
        let name = (info["Name"] as? String) ?? ""
        let artist = (info["Artist"] as? String) ?? ""
        let album = (info["Album"] as? String) ?? ""

        if !name.isEmpty {
            let isSameSong = (self.currentTrack.title == name && self.currentTrack.artist == artist)
            let cacheKey = artworkCacheKey(title: name, artist: artist)
            let existingArtwork = isSameSong ? self.currentTrack.artworkData : artworkCache[cacheKey]

            self.currentTrack = NowPlayingTrack(
                title: name,
                artist: artist,
                album: album,
                artworkURL: self.currentTrack.artworkURL,
                artworkData: existingArtwork,
                isPlaying: isPlaying,
                elapsedSeconds: self.currentTrack.elapsedSeconds,
                durationSeconds: self.currentTrack.durationSeconds > 0 ? self.currentTrack.durationSeconds : 210,
                serviceSource: .spotify,
                canControlPlayback: true,
                limitationNotice: spotifyLimitationNotice
            )

            if existingArtwork == nil, LaunchpadViewModel.isLaunchpadVisible {
                resolveArtwork(for: name, artist: artist, album: album, fallbackURL: self.currentTrack.artworkURL)
            }
        }
    }

    private func startPolling() {
        timer?.invalidate()
        progressTimer?.invalidate()

        let newTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, LaunchpadViewModel.isLaunchpadVisible else { return }
                self.refreshNowPlaying()
            }
        }
        newTimer.tolerance = 2.5
        timer = newTimer

        lastProgressTickUptime = ProcessInfo.processInfo.systemUptime
        let newProgressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, LaunchpadViewModel.isLaunchpadVisible else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = max(0, min(4.0, now - self.lastProgressTickUptime))
                self.lastProgressTickUptime = now
                guard self.currentTrack.isPlaying, self.currentTrack.hasTrack, self.currentTrack.durationSeconds > 0 else { return }
                let nextElapsed = min(self.currentTrack.durationSeconds, self.currentTrack.elapsedSeconds + delta)
                if Int(nextElapsed.rounded()) != Int(self.currentTrack.elapsedSeconds.rounded()) {
                    self.currentTrack.elapsedSeconds = nextElapsed
                }
            }
        }
        newProgressTimer.tolerance = 0.5
        progressTimer = newProgressTimer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Apple Music (MusicKit Officiel)

    public func connectAppleMusic() {
        Task {
            appleMusicStatus = .connecting
            let status = await MusicAuthorization.request()
            switch status {
            case .authorized:
                UserDefaults.standard.set(true, forKey: "AppleMusicConnected")
                await checkAppleMusicSubscription()
                refreshNowPlaying()
            case .denied:
                UserDefaults.standard.set(false, forKey: "AppleMusicConnected")
                appleMusicStatus = .restricted(reason: loc("music.apple.permission_denied"))
            case .restricted:
                UserDefaults.standard.set(false, forKey: "AppleMusicConnected")
                appleMusicStatus = .restricted(reason: loc("music.apple.restricted"))
            case .notDetermined:
                UserDefaults.standard.set(false, forKey: "AppleMusicConnected")
                appleMusicStatus = .notConnected
            @unknown default:
                UserDefaults.standard.set(false, forKey: "AppleMusicConnected")
                appleMusicStatus = .notConnected
            }
        }
    }

    public func disconnectAppleMusic() {
        UserDefaults.standard.set(false, forKey: "AppleMusicConnected")
        appleMusicStatus = .notConnected
        appleMusicCanPlayCatalog = false
        appleMusicSubscriptionDescription = ""
        if currentTrack.serviceSource == .appleMusic {
            currentTrack = .empty
        }
    }

    private func verifyAppleMusicAuthorization() {
        let status = MusicAuthorization.currentStatus
        switch status {
        case .authorized:
            Task { await checkAppleMusicSubscription() }
        case .denied:
            appleMusicStatus = .restricted(reason: loc("music.apple.permission_denied"))
        case .restricted:
            appleMusicStatus = .restricted(reason: loc("music.apple.restricted"))
        default:
            appleMusicStatus = .notConnected
        }
    }

    private func checkAppleMusicSubscription() async {
        do {
            let subscription = try await MusicSubscription.current
            self.appleMusicCanPlayCatalog = subscription.canPlayCatalogContent
            if subscription.canPlayCatalogContent {
                self.appleMusicSubscriptionDescription = loc("music.apple.subscription_active")
                self.appleMusicStatus = .connected(details: loc("music.apple.subscription_active"))
            } else {
                self.appleMusicSubscriptionDescription = loc("music.apple.subscription_needed")
                self.appleMusicStatus = .connected(details: loc("music.apple.subscription_needed"))
            }
        } catch {
            self.appleMusicCanPlayCatalog = false
            self.appleMusicStatus = .connected(details: loc("music.apple.authorized"))
        }
    }

    // MARK: - Spotify (OAuth 2.0 PKCE Officiel)

    public func connectSpotify() {
        let clientID = effectiveSpotifyClientID
        let verifier = Self.generateCodeVerifier()
        let challenge = Self.generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

        self.pendingPKCEVerifier = verifier
        self.pendingAuthState = state
        self.spotifyStatus = .connecting

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.spotifyRedirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state user-read-currently-playing user-library-read user-top-read playlist-read-private")
        ]

        guard let authURL = components.url else {
            self.spotifyStatus = .error(message: "URL d'authentification invalide.")
            return
        }

        authSession?.cancel()
        authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "launchpad") { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error = error as? ASWebAuthenticationSessionError {
                    if error.code == .canceledLogin {
                        // Annulation par l'utilisateur : retour propre sans message alarmiste
                        if !self.spotifyStatus.isConnected {
                            self.spotifyStatus = .notConnected
                        }
                        return
                    }
                    self.spotifyStatus = .error(message: error.localizedDescription)
                    return
                }

                guard let callbackURL,
                      let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    self.spotifyStatus = .error(message: loc("music.spotify.access_denied"))
                    return
                }

                if let returnedState = urlComponents.queryItems?.first(where: { $0.name == "state" })?.value,
                   returnedState != self.pendingAuthState {
                    self.spotifyStatus = .error(message: "Contrôle de sécurité (state) échoué.")
                    return
                }

                if let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value,
                   let verifier = self.pendingPKCEVerifier {
                    await self.exchangeSpotifyCodeForToken(code: code, verifier: verifier)
                } else if let errorMsg = urlComponents.queryItems?.first(where: { $0.name == "error" })?.value {
                    self.spotifyStatus = .error(message: "Erreur Spotify : \(errorMsg)")
                }
            }
        }

        authSession?.presentationContextProvider = authAnchorProvider
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }

    public func disconnectSpotify() {
        KeychainHelper.delete(key: "spotify_access_token")
        KeychainHelper.delete(key: "spotify_refresh_token")
        KeychainHelper.delete(key: "spotify_token_expiry")
        UserDefaults.standard.removeObject(forKey: "SpotifyUserDisplayName")
        UserDefaults.standard.removeObject(forKey: "SpotifyProductType")

        spotifyStatus = .notConnected
        spotifyUserDisplayName = nil
        spotifyProductType = nil
        spotifyLimitationNotice = nil

        if currentTrack.serviceSource == .spotify {
            currentTrack = .empty
        }
    }

    private func exchangeSpotifyCodeForToken(code: String, verifier: String) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "authorization_code",
            "client_id": effectiveSpotifyClientID,
            "code": code,
            "redirect_uri": Self.spotifyRedirectURI,
            "code_verifier": verifier
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errString = String(data: data, encoding: .utf8) ?? "Erreur inconnue"
                self.spotifyStatus = .error(message: "Échange de jeton échoué : \(errString)")
                return
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                KeychainHelper.saveString(key: "spotify_access_token", value: accessToken)

                if let refreshToken = json["refresh_token"] as? String {
                    KeychainHelper.saveString(key: "spotify_refresh_token", value: refreshToken)
                }

                if let expiresIn = json["expires_in"] as? Double {
                    let expiryDate = Date().addingTimeInterval(expiresIn)
                    KeychainHelper.saveString(key: "spotify_token_expiry", value: String(expiryDate.timeIntervalSince1970))
                }

                await fetchSpotifyProfile(accessToken: accessToken)
                self.refreshNowPlaying()
            }
        } catch {
            self.spotifyStatus = .error(message: error.localizedDescription)
        }
    }

    private func refreshSpotifyTokenIfNeeded() async -> String? {
        guard let expiryString = KeychainHelper.loadString(key: "spotify_token_expiry"),
              let expiryTimestamp = Double(expiryString),
              let refreshToken = KeychainHelper.loadString(key: "spotify_refresh_token") else {
            return KeychainHelper.loadString(key: "spotify_access_token")
        }

        // Si le jeton est encore valide au moins 60 secondes, on l'utilise
        if Date().timeIntervalSince1970 < (expiryTimestamp - 60) {
            return KeychainHelper.loadString(key: "spotify_access_token")
        }

        // Sinon, renouvellement via refresh_token
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "refresh_token",
            "client_id": effectiveSpotifyClientID,
            "refresh_token": refreshToken
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String else {
                return nil
            }

            KeychainHelper.saveString(key: "spotify_access_token", value: newAccessToken)
            if let expiresIn = json["expires_in"] as? Double {
                let expiryDate = Date().addingTimeInterval(expiresIn)
                KeychainHelper.saveString(key: "spotify_token_expiry", value: String(expiryDate.timeIntervalSince1970))
            }
            if let newRefresh = json["refresh_token"] as? String {
                KeychainHelper.saveString(key: "spotify_refresh_token", value: newRefresh)
            }
            return newAccessToken
        } catch {
            return nil
        }
    }

    private func fetchSpotifyProfile(accessToken: String) async {
        guard let url = URL(string: "https://api.spotify.com/v1/me") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let displayName = (json["display_name"] as? String) ?? "Spotify"
            let product = (json["product"] as? String) ?? "free"

            self.spotifyUserDisplayName = displayName
            self.spotifyProductType = product
            UserDefaults.standard.set(displayName, forKey: "SpotifyUserDisplayName")
            UserDefaults.standard.set(product, forKey: "SpotifyProductType")

            if product.lowercased() == "premium" {
                self.spotifyLimitationNotice = nil
                self.spotifyStatus = .connected(details: "\(displayName) • \(loc("music.spotify.premium_active"))")
            } else {
                self.spotifyLimitationNotice = loc("music.spotify.free_notice")
                self.spotifyStatus = .connected(details: "\(displayName) • \(loc("music.spotify.free_notice"))")
            }
        } catch {
            self.spotifyStatus = .connected(details: "Connecté")
        }
    }

    private func verifySpotifyConnection() {
        Task {
            if let token = await refreshSpotifyTokenIfNeeded() {
                await fetchSpotifyProfile(accessToken: token)
            } else {
                spotifyStatus = .notConnected
            }
        }
    }

    // MARK: - Actualisation unifiée des métadonnées (Now Playing)

    public func refreshNowPlaying(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if isRefreshingNowPlaying { return }
        if !force && (now - lastRefreshUptime) < 1.1 { return }

        isRefreshingNowPlaying = true
        lastRefreshUptime = now

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRefreshingNowPlaying = false
                self.lastRefreshUptime = ProcessInfo.processInfo.systemUptime
            }
            await self.performRefreshNowPlaying(force: force)
        }
    }

    private func assignCurrentTrack(_ newTrack: NowPlayingTrack) {
        lastProgressTickUptime = ProcessInfo.processInfo.systemUptime
        if currentTrack != newTrack {
            currentTrack = newTrack
        }
    }

    private func performRefreshNowPlaying(force: Bool = false) async {
        // 1. Si un service particulier est explicitement forcé par l'utilisateur
        if preferredService == .spotify {
            if spotifyStatus.isConnected, let track = await fetchSpotifyCurrentlyPlaying() {
                assignCurrentTrack(track)
                return
            }
            if let localSpotify = await fetchLocalSpotifyTrack() {
                assignCurrentTrack(localSpotify)
                return
            }
        } else if preferredService == .appleMusic {
            if let track = await fetchLocalAppleMusicTrack() {
                assignCurrentTrack(track)
                return
            }
        }

        // 2. Mode automatique (.system ou préférence par défaut) :
        // On interroge d'abord les lecteurs dédiés (0 sous-processus externe, ultra-léger en CPU).
        async let spotifyWebTrack = spotifyStatus.isConnected ? fetchSpotifyCurrentlyPlaying() : nil
        async let localAppleTrack = fetchLocalAppleMusicTrack()
        async let localSpotifyTrack = fetchLocalSpotifyTrack()

        let (spotifyWeb, localApple, localSpotify) = await (spotifyWebTrack, localAppleTrack, localSpotifyTrack)
        let dedicatedCandidates = [spotifyWeb, localApple, localSpotify].compactMap { $0 }

        // Si Musique ou Spotify est en cours de lecture active, on évite complètement de lancer osascript !
        if let playingDedicated = dedicatedCandidates.first(where: { $0.isPlaying }) {
            assignCurrentTrack(playingDedicated)
            return
        }

        // 3. Seulement si aucun lecteur dédié ne joue, on interroge la lecture système universelle (avec limitation de fréquence)
        let system = await fetchSystemTrack(force: force)
        let candidates = dedicatedCandidates + [system].compactMap { $0 }

        // Priorité 1 : Le lecteur actuellement en cours de lecture
        if let playingCandidate = candidates.first(where: { $0.isPlaying }) {
            assignCurrentTrack(playingCandidate)
            return
        }

        // Priorité 2 : Si aucun ne joue actuellement, afficher le dernier morceau en pause disponible
        if let pausedCandidate = candidates.first(where: { $0.hasTrack }) {
            assignCurrentTrack(pausedCandidate)
            return
        }

        // Priorité 3 : plus aucune lecture nulle part (application fermée) → on vide le widget
        // plutôt que d'afficher indéfiniment un morceau périmé.
        if currentTrack.hasTrack, currentTrack.serviceSource == .system {
            assignCurrentTrack(.empty)
        }
    }

    // MARK: - Lecture système universelle (navigateurs, VLC, lecteurs vidéo…)

    private func fetchSystemTrack(force: Bool = false) async -> NowPlayingTrack? {
        let now = ProcessInfo.processInfo.systemUptime
        if !force, (now - lastSystemFetchUptime) < 12.0 {
            if var cached = cachedSystemTrack {
                if cached.isPlaying, cached.durationSeconds > 0 {
                    let elapsedSinceFetch = max(0, now - lastSystemFetchUptime)
                    cached.elapsedSeconds = min(cached.durationSeconds, cached.elapsedSeconds + elapsedSinceFetch)
                }
                return cached
            }
            return nil
        }

        let knownSystemTitle: String? = (currentTrack.serviceSource == .system && currentTrack.artworkData != nil && !currentTrack.title.isEmpty)
            ? currentTrack.title
            : nil
        lastSystemFetchUptime = now
        guard let snap = await SystemNowPlayingClient.fetch(skipArtworkForTitle: knownSystemTitle) else {
            cachedSystemTrack = nil
            return nil
        }

        let isSameSong = (currentTrack.title == snap.title && currentTrack.artist == snap.artist
                          && currentTrack.serviceSource == .system)
        let cacheKey = artworkCacheKey(title: snap.title, artist: snap.artist.isEmpty ? snap.bundleID : snap.artist)
        let artwork = snap.artworkData ?? (isSameSong ? currentTrack.artworkData : artworkCache[cacheKey])

        var track = NowPlayingTrack(
            title: snap.title,
            artist: snap.artist.isEmpty ? snap.appName : snap.artist,
            album: snap.album,
            artworkURL: nil,
            artworkData: artwork,
            isPlaying: snap.isPlaying,
            elapsedSeconds: snap.elapsed,
            durationSeconds: snap.duration,
            serviceSource: .system,
            canControlPlayback: true,
            limitationNotice: nil
        )
        track.sourceBundleID = snap.bundleID
        track.sourceAppName = snap.appName

        if let data = snap.artworkData {
            storeArtwork(data, forKey: cacheKey)
        } else if artwork == nil, !Self.isBrowser(bundleID: snap.bundleID), !snap.artist.isEmpty {
            // Miniature : recherche de la pochette officielle (les vidéos de navigateur n'ont pas
            // de correspondance fiable, on garde alors l'icône de l'application source).
            resolveArtwork(for: snap.title, artist: snap.artist, album: snap.album, allowLocalMusicApp: false)
        }
        cachedSystemTrack = track
        return track
    }

    private static func isBrowser(bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return ["chrome", "safari", "firefox", "zen", "arc", "brave", "edge", "opera", "vivaldi", "chromium", "browser"]
            .contains { id.contains($0) }
    }

    private func fetchSpotifyCurrentlyPlaying() async -> NowPlayingTrack? {
        guard let token = await refreshSpotifyTokenIfNeeded(),
              let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 204 {
                // Rien en cours de lecture
                return nil
            }
            guard httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = json["item"] as? [String: Any] else {
                return nil
            }

            let title = (item["name"] as? String) ?? ""
            let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
            let albumDict = item["album"] as? [String: Any]
            let album = (albumDict?["name"] as? String) ?? ""
            let isPlaying = (json["is_playing"] as? Bool) ?? false
            let progressMs = (json["progress_ms"] as? Double) ?? 0
            let durationMs = (item["duration_ms"] as? Double) ?? 0

            var artworkURL: URL? = nil
            if let images = albumDict?["images"] as? [[String: Any]],
               let firstImage = images.first,
               let urlString = firstImage["url"] as? String {
                artworkURL = URL(string: urlString)
            }

            let isSameSong = (self.currentTrack.title == title && self.currentTrack.artist == artists)
            let cacheKey = artworkCacheKey(title: title, artist: artists)
            let existingArtwork = isSameSong ? self.currentTrack.artworkData : artworkCache[cacheKey]

            let track = NowPlayingTrack(
                title: title,
                artist: artists,
                album: album,
                artworkURL: artworkURL,
                artworkData: existingArtwork,
                isPlaying: isPlaying,
                elapsedSeconds: progressMs / 1000.0,
                durationSeconds: durationMs / 1000.0,
                serviceSource: .spotify,
                canControlPlayback: (spotifyProductType?.lowercased() == "premium"),
                limitationNotice: spotifyLimitationNotice
            )

            if existingArtwork == nil {
                resolveArtwork(for: title, artist: artists, album: album, fallbackURL: artworkURL)
            }
            return track
        } catch {
            return nil
        }
    }

    // MARK: - Résolution Avancée et Cache de Pochettes d'Album

    private static let maxArtworkCacheEntries = 30

    private func storeArtwork(_ data: Data, forKey key: String) {
        if artworkCache.count >= Self.maxArtworkCacheEntries, artworkCache[key] == nil {
            // Éviction légère de la moitié des entrées pour borner l'empreinte RAM
            let keysToRemove = Array(artworkCache.keys.prefix(Self.maxArtworkCacheEntries / 2))
            for k in keysToRemove { artworkCache.removeValue(forKey: k) }
        }
        artworkCache[key] = data
    }

    private func artworkCacheKey(title: String, artist: String) -> String {
        "\(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|||\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func resolveArtwork(for title: String, artist: String, album: String, fallbackURL: URL? = nil, allowLocalMusicApp: Bool = true) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let cacheKey = artworkCacheKey(title: trimmedTitle, artist: trimmedArtist)

        // 1. Vérifier si l'image est déjà en cache mémoire
        if let cachedData = artworkCache[cacheKey] {
            if self.currentTrack.title == trimmedTitle {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.currentTrack.artworkData = cachedData
                }
            }
            return
        }

        // Éviter les requêtes concurrentes en doublon pour le même morceau
        if inFlightArtworkQueries.contains(cacheKey) { return }
        inFlightArtworkQueries.insert(cacheKey)

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.inFlightArtworkQueries.remove(cacheKey)
            }

            // Étape A : Télécharger depuis le fallbackURL (ex: Spotify CDN) si présent
            if let fallbackURL {
                if let data = await self.fetchArtworkData(from: fallbackURL) {
                    self.storeArtwork(data, forKey: cacheKey)
                    if self.currentTrack.title == trimmedTitle {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.currentTrack.artworkData = data
                        }
                    }
                    return
                }
            }

            // Étape B : Tenter d'extraire la pochette locale via AppleScript (pour fichiers locaux MP3/AAC)
            let localData: Data? = allowLocalMusicApp ? await Task.detached(priority: .userInitiated) {
                Self.extractLocalMusicArtwork()
            }.value : nil

            if let localData, !localData.isEmpty, NSImage(data: localData) != nil {
                self.storeArtwork(localData, forKey: cacheKey)
                if self.currentTrack.title == trimmedTitle {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.currentTrack.artworkData = localData
                    }
                }
                return
            }

            // Étape C : Requête sur l'API officielle iTunes Search (Apple CDN, cover HD 600x600)
            if let remoteData = await self.searchArtworkOnITunes(title: trimmedTitle, artist: trimmedArtist) {
                self.storeArtwork(remoteData, forKey: cacheKey)
                if self.currentTrack.title == trimmedTitle {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.currentTrack.artworkData = remoteData
                    }
                }
                return
            }
        }
    }

    private func searchArtworkOnITunes(title: String, artist: String) async -> Data? {
        // Nettoyer les mentions feat/ft/avec pour maximiser les correspondances de recherche
        let cleanTitle = title
            .replacingOccurrences(of: #"\s*[\(\[][fF]eat[^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[\(\[][fF]t[^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanArtist = artist
            .components(separatedBy: ",")[0]
            .components(separatedBy: "&")[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let queries = [
            "\(cleanTitle) \(cleanArtist)",
            "\(title) \(artist)",
            cleanTitle
        ]

        for query in queries {
            guard !query.isEmpty,
                  let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=3") else {
                continue
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 6.0
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  !results.isEmpty else {
                continue
            }

            for result in results {
                if let rawURL = (result["artworkUrl100"] as? String) ?? (result["artworkUrl60"] as? String) {
                    let highResURLString = rawURL
                        .replacingOccurrences(of: "100x100bb", with: "600x600bb")
                        .replacingOccurrences(of: "60x60bb", with: "600x600bb")

                    if let highResURL = URL(string: highResURLString),
                       let imgData = await fetchArtworkData(from: highResURL) {
                        return imgData
                    }
                }
            }
        }
        return nil
    }

    nonisolated private static func extractLocalMusicArtwork() -> Data? {
        let scriptSource = """
        if application "Music" is running then
            tell application "Music"
                try
                    if exists (artwork 1 of current track) then
                        set rawData to raw data of artwork 1 of current track
                        return rawData
                    end if
                end try
            end tell
        end if
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    private func fetchArtworkData(from url: URL) async -> Data? {
        if let cached = artworkCache[url.absoluteString] { return cached }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              !data.isEmpty,
              NSImage(data: data) != nil else {
            return nil
        }
        storeArtwork(data, forKey: url.absoluteString)
        return data
    }

    private static func parseDouble(_ string: String) -> Double? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private static let appleMusicQueryScriptSource = """
    tell application "Music"
        if not running then return ""
        try
            set pState to (player state as string)
            if pState is "playing" or pState is "paused" then
                set trName to ""
                set trArtist to ""
                set trAlbum to ""
                set trPos to 0
                set trDur to 0
                try
                    set trName to (name of current track as string)
                end try
                try
                    set trArtist to (artist of current track as string)
                end try
                try
                    set trAlbum to (album of current track as string)
                end try
                try
                    set trPos to (player position as string)
                end try
                try
                    set trDur to (duration of current track as string)
                end try
                return pState & "|||" & trName & "|||" & trArtist & "|||" & trAlbum & "|||" & trPos & "|||" & trDur
            end if
        on error
            return ""
        end try
    end tell
    return ""
    """

    private static let spotifyQueryScriptSource = """
    tell application "Spotify"
        if not running then return ""
        try
            set pState to (player state as string)
            if pState is "playing" or pState is "paused" then
                set trName to ""
                set trArtist to ""
                set trAlbum to ""
                set trPos to 0
                set trDur to 0
                set trArt to ""
                try
                    set trName to (name of current track as string)
                end try
                try
                    set trArtist to (artist of current track as string)
                end try
                try
                    set trAlbum to (album of current track as string)
                end try
                try
                    set trPos to (player position as string)
                end try
                try
                    set trDur to ((duration of current track) / 1000 as string)
                end try
                try
                    set trArt to (artwork url of current track as string)
                end try
                return pState & "|||" & trName & "|||" & trArtist & "|||" & trAlbum & "|||" & trPos & "|||" & trDur & "|||" & trArt
            end if
        on error
            return ""
        end try
    end tell
    return ""
    """

    nonisolated private static let appleScriptQueryQueue = DispatchQueue(label: "me.LaucnhPad.music.applescript", qos: .utility)
    nonisolated(unsafe) private static var compiledAppleMusicQueryScript: NSAppleScript?
    nonisolated(unsafe) private static var compiledSpotifyQueryScript: NSAppleScript?

    nonisolated private static func executeCachedAppleMusicQuery() -> String? {
        appleScriptQueryQueue.sync {
            if compiledAppleMusicQueryScript == nil {
                let script = NSAppleScript(source: appleMusicQueryScriptSource)
                var compileErr: NSDictionary?
                script?.compileAndReturnError(&compileErr)
                compiledAppleMusicQueryScript = script
            }
            var error: NSDictionary?
            return compiledAppleMusicQueryScript?.executeAndReturnError(&error).stringValue
        }
    }

    nonisolated private static func executeCachedSpotifyQuery() -> String? {
        appleScriptQueryQueue.sync {
            if compiledSpotifyQueryScript == nil {
                let script = NSAppleScript(source: spotifyQueryScriptSource)
                var compileErr: NSDictionary?
                script?.compileAndReturnError(&compileErr)
                compiledSpotifyQueryScript = script
            }
            var error: NSDictionary?
            return compiledSpotifyQueryScript?.executeAndReturnError(&error).stringValue
        }
    }

    private func fetchLocalAppleMusicTrack() async -> NowPlayingTrack? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return nil
        }

        let result = await Task.detached(priority: .utility) { () -> String? in
            Self.executeCachedAppleMusicQuery()
        }.value

        guard let result, !result.isEmpty else { return nil }

        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let isPlaying = parts[0] == "playing"
        let title = parts[1]
        let artist = parts[2]
        let album = parts[3]
        let elapsed = Self.parseDouble(parts[4]) ?? 0
        let duration = Self.parseDouble(parts[5]) ?? 240

        guard !title.isEmpty else { return nil }

        let isSameSong = (self.currentTrack.title == title && self.currentTrack.artist == artist)
        let cacheKey = artworkCacheKey(title: title, artist: artist)
        let existingArtwork = isSameSong ? self.currentTrack.artworkData : artworkCache[cacheKey]

        let track = NowPlayingTrack(
            title: title,
            artist: artist,
            album: album,
            artworkURL: self.currentTrack.artworkURL,
            artworkData: existingArtwork,
            isPlaying: isPlaying,
            elapsedSeconds: elapsed,
            durationSeconds: max(1, duration),
            serviceSource: .appleMusic,
            canControlPlayback: true,
            limitationNotice: nil
        )

        if existingArtwork == nil {
            resolveArtwork(for: title, artist: artist, album: album)
        }
        return track
    }

    private func fetchLocalSpotifyTrack() async -> NowPlayingTrack? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            return nil
        }

        let result = await Task.detached(priority: .utility) { () -> String? in
            Self.executeCachedSpotifyQuery()
        }.value

        guard let result, !result.isEmpty else { return nil }

        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let isPlaying = parts[0] == "playing"
        let title = parts[1]
        let artist = parts[2]
        let album = parts[3]
        let elapsed = Self.parseDouble(parts[4]) ?? 0
        let duration = Self.parseDouble(parts[5]) ?? 210
        let artworkUrlString = parts.count > 6 ? parts[6] : ""

        guard !title.isEmpty else { return nil }

        let artURL = URL(string: artworkUrlString)
        let isSameSong = (self.currentTrack.title == title && self.currentTrack.artist == artist)
        let cacheKey = artworkCacheKey(title: title, artist: artist)
        let existingArtwork = isSameSong ? self.currentTrack.artworkData : artworkCache[cacheKey]

        let track = NowPlayingTrack(
            title: title,
            artist: artist,
            album: album,
            artworkURL: artURL,
            artworkData: existingArtwork,
            isPlaying: isPlaying,
            elapsedSeconds: elapsed,
            durationSeconds: max(1, duration),
            serviceSource: .spotify,
            canControlPlayback: true,
            limitationNotice: spotifyLimitationNotice
        )

        if existingArtwork == nil {
            resolveArtwork(for: title, artist: artist, album: album, fallbackURL: artURL)
        }
        return track
    }

    // MARK: - Contrôles de Lecture (Play / Pause / Next / Prev)

    /// Déplace la lecture à une position (0…1) de la durée du morceau en cours.
    public func seek(toFraction fraction: Double) {
        let track = currentTrack
        guard track.hasTrack, track.durationSeconds > 0 else { return }
        let seconds = min(track.durationSeconds, max(0, fraction * track.durationSeconds))
        currentTrack.elapsedSeconds = seconds

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch track.serviceSource {
            case .system:
                let accepted = await SystemNowPlayingClient.seek(to: seconds)
                if !accepted { await self.seekSourceApp(track, seconds: seconds) }
            case .appleMusic:
                let done = await self.runAppleScript(Self.seekScript(app: "Music", seconds: seconds))
                if !done { _ = await SystemNowPlayingClient.seek(to: seconds) }
            case .spotify:
                let done = await self.runAppleScript(Self.seekScript(app: "Spotify", seconds: seconds))
                if !done { _ = await SystemNowPlayingClient.seek(to: seconds) }
                if self.spotifyStatus.isConnected && self.spotifyProductType?.lowercased() == "premium" {
                    if let token = await self.refreshSpotifyTokenIfNeeded(),
                       let url = URL(string: "https://api.spotify.com/v1/me/player/seek?position_ms=\(Int(seconds * 1000))") {
                        var request = URLRequest(url: url)
                        request.httpMethod = "PUT"
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        _ = try? await URLSession.shared.data(for: request)
                    }
                }
            case .none:
                break
            }
            self.scheduleRefresh([0.5, 1.2])
        }
    }

    private func scheduleRefresh(_ delays: [Double]) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshNowPlaying(force: true)
            }
        }
    }

    /// Commande le lecteur actif. Les touches multimédia matérielles sont privilégiées
    /// (elles fonctionnent avec les navigateurs, VLC, etc.) ; MediaRemote sert de repli
    /// quand l'app n'a pas l'autorisation Accessibilité.
    private func sendSystemCommand(_ command: SystemMediaCommand) {
        if command == .togglePlayPause { currentTrack.isPlaying.toggle() }
        let track = currentTrack
        Task { @MainActor [weak self] in
            guard let self else { return }
            if SystemNowPlayingClient.canSendHardwareMediaKeys {
                SystemMediaKey.send(command)
            } else {
                let accepted = await SystemNowPlayingClient.send(command)
                if !accepted {
                    await self.controlSourceApp(track, command: command)
                }
            }
            self.scheduleRefresh([0.35, 0.9])
        }
    }

    /// Envoie une commande de repli après l'échec d'un contrôle direct (AppleScript).
    private func sendFallbackCommand(_ command: SystemMediaCommand) async {
        if SystemNowPlayingClient.canSendHardwareMediaKeys {
            SystemMediaKey.send(command)
        } else {
            _ = await SystemNowPlayingClient.send(command)
        }
    }

    public func togglePlayPause() {
        if currentTrack.serviceSource == .system {
            sendSystemCommand(.togglePlayPause)
        } else if currentTrack.serviceSource == .spotify {
            toggleSpotifyPlayback()
        } else {
            toggleAppleMusicPlayback()
        }
    }

    public func nextTrack() {
        if currentTrack.serviceSource == .system {
            sendSystemCommand(.nextTrack)
        } else if currentTrack.serviceSource == .spotify {
            nextSpotifyTrack()
        } else {
            nextAppleMusicTrack()
        }
    }

    public func previousTrack() {
        if currentTrack.serviceSource == .system {
            sendSystemCommand(.previousTrack)
        } else if currentTrack.serviceSource == .spotify {
            previousSpotifyTrack()
        } else {
            previousAppleMusicTrack()
        }
    }

    /// Contrôle le lecteur système même lorsque ses métadonnées ne sont pas (encore) disponibles.
    public func toggleSystemPlayback() { sendSystemCommand(.togglePlayPause) }
    public func nextSystemTrack() { sendSystemCommand(.nextTrack) }
    public func previousSystemTrack() { sendSystemCommand(.previousTrack) }

    private func toggleAppleMusicPlayback() {
        currentTrack.isPlaying.toggle()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let done = await self.runAppleScript("""
            tell application "Music"
                if it is running then
                    playpause
                    return "ok"
                else
                    return "not-running"
                end if
            end tell
            """)
            if !done { await sendFallbackCommand(.togglePlayPause) }
            self.scheduleRefresh([0.35])
        }
    }

    private func nextAppleMusicTrack() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let done = await self.runAppleScript("""
            tell application "Music"
                if it is running then
                    next track
                    return "ok"
                else
                    return "not-running"
                end if
            end tell
            """)
            if !done { await sendFallbackCommand(.nextTrack) }
            self.scheduleRefresh([0.4])
        }
    }

    private func previousAppleMusicTrack() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let done = await self.runAppleScript("""
            tell application "Music"
                if it is running then
                    previous track
                    return "ok"
                else
                    return "not-running"
                end if
            end tell
            """)
            if !done { await sendFallbackCommand(.previousTrack) }
            self.scheduleRefresh([0.4])
        }
    }

    /// Contrôle direct (AppleScript) de l'application qui publie la lecture, utilisé
    /// quand MediaRemote n'accepte pas la commande.
    private func controlSourceApp(_ track: NowPlayingTrack, command: SystemMediaCommand) async {
        let bundle = track.sourceBundleID.lowercased()
        let app: String?
        if bundle.contains("spotify") || track.serviceSource == .spotify {
            app = "Spotify"
        } else if bundle.contains("music") || track.serviceSource == .appleMusic {
            app = "Music"
        } else {
            app = nil
        }
        guard let app else { return }

        let verb: String
        switch command {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .togglePlayPause: verb = "playpause"
        case .nextTrack: verb = "next track"
        case .previousTrack: verb = "previous track"
        }
        _ = await runAppleScript("""
        tell application "\(app)"
            if it is running then
                \(verb)
                return "ok"
            else
                return "not-running"
            end if
        end tell
        """)
    }

    private func seekSourceApp(_ track: NowPlayingTrack, seconds: Double) async {
        let bundle = track.sourceBundleID.lowercased()
        if bundle.contains("spotify") || track.serviceSource == .spotify {
            _ = await runAppleScript(Self.seekScript(app: "Spotify", seconds: seconds))
        } else if bundle.contains("music") || track.serviceSource == .appleMusic {
            _ = await runAppleScript(Self.seekScript(app: "Music", seconds: seconds))
        }
    }

    private static func seekScript(app: String, seconds: Double) -> String {
        """
        tell application "\(app)"
            if it is running then
                set player position to \(seconds)
                return "ok"
            else
                return "not-running"
            end if
        end tell
        """
    }

    private func toggleSpotifyPlayback() {
        currentTrack.isPlaying.toggle()
        let shouldPlay = currentTrack.isPlaying

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Spotify local : commande instantanée via AppleScript.
            let done = await self.runAppleScript("""
            tell application "Spotify"
                if it is running then
                    playpause
                    return "ok"
                else
                    return "not-running"
                end if
            end tell
            """)
            // Si Spotify n'est pas lancé sur ce Mac (lecture distante), on tente MediaRemote.
            if !done { await sendFallbackCommand(.togglePlayPause) }

            // Et si connecté à la Web API Spotify avec Premium, synchronisation Cloud.
            if self.spotifyStatus.isConnected && self.spotifyProductType?.lowercased() == "premium" {
                if let token = await self.refreshSpotifyTokenIfNeeded() {
                    let endpoint = shouldPlay ? "play" : "pause"
                    if let url = URL(string: "https://api.spotify.com/v1/me/player/\(endpoint)") {
                        var request = URLRequest(url: url)
                        request.httpMethod = "PUT"
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        _ = try? await URLSession.shared.data(for: request)
                    }
                }
            }
            self.scheduleRefresh([0.35])
        }
    }

    private func nextSpotifyTrack() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let done = await self.runAppleScript("""
            tell application "Spotify"
                if it is running then
                    next track
                    return "ok"
                else
                    return "not-running"
                end if
            end tell
            """)
            if !done { await sendFallbackCommand(.nextTrack) }

            if self.spotifyStatus.isConnected && self.spotifyProductType?.lowercased() == "premium" {
                if let token = await self.refreshSpotifyTokenIfNeeded(),
                   let url = URL(string: "https://api.spotify.com/v1/me/player/next") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    _ = try? await URLSession.shared.data(for: request)
                }
            }
            self.scheduleRefresh([0.4])
        }
    }

    private func previousSpotifyTrack() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let done = await self.runAppleScript("""
            tell application "Spotify"
                if it is running then
                    previous track
                    return "ok"
                else
                    return "not-running"
                end if
            end tell
            """)
            if !done { await sendFallbackCommand(.previousTrack) }

            if self.spotifyStatus.isConnected && self.spotifyProductType?.lowercased() == "premium" {
                if let token = await self.refreshSpotifyTokenIfNeeded(),
                   let url = URL(string: "https://api.spotify.com/v1/me/player/previous") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    _ = try? await URLSession.shared.data(for: request)
                }
            }
            self.scheduleRefresh([0.4])
        }
    }

    // MARK: - Lancement de Musique Aléatoire sur le Compte

    public func toggleMute() {
        isMuted.toggle()
        let muteState = isMuted ? "with" : "without"
        executeAppleScript("set volume \(muteState) output muted")
    }

    public func openMusicApp() {
        playRandomMusic()
    }

    public func playRandomMusic() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLaunchingRandomTrack = true
            defer {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.isLaunchingRandomTrack = false
                }
            }

            let service = self.determineTargetMusicService()
            switch service {
            case .spotify:
                await self.playRandomSpotifyTrack()
            case .appleMusic, .system, .none:
                await self.playRandomAppleMusicTrack()
            }

            // Échelonne plusieurs rafraîchissements pour détecter le morceau dès qu'il démarre
            for delayMs in [400, 900, 1600, 2400] {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
                    self?.refreshNowPlaying()
                }
            }
        }
    }

    private func determineTargetMusicService() -> MusicServiceSource {
        if preferredService == .spotify { return .spotify }
        if preferredService == .appleMusic { return .appleMusic }

        // Si un seul des services est connecté
        if spotifyStatus.isConnected && !appleMusicStatus.isConnected {
            return .spotify
        }
        if appleMusicStatus.isConnected && !spotifyStatus.isConnected {
            return .appleMusic
        }

        // Si Spotify tourne en local sur le Mac
        if isAppRunning(bundleID: "com.spotify.client") {
            return .spotify
        }
        // Si Musique tourne en local sur le Mac
        if isAppRunning(bundleID: "com.apple.Music") {
            return .appleMusic
        }

        // Par défaut si Spotify est connecté
        if spotifyStatus.isConnected {
            return .spotify
        }

        // Sinon application Musique (Apple Music / Bibliothèque locale macOS)
        return .appleMusic
    }

    private func isAppRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: - Lecture Aléatoire Spotify

    private func playRandomSpotifyTrack() async {
        // 1. Tenter la Web API Spotify si connecté avec jeton
        if spotifyStatus.isConnected, let token = await refreshSpotifyTokenIfNeeded() {
            // Chercher dans les titres likés / enregistrés de l'utilisateur
            if let trackURI = await fetchRandomSpotifySavedTrack(token: token) {
                let started = await startSpotifyPlaybackWithTrack(uri: trackURI, token: token)
                if started {
                    executeAppleScript("tell application \"Spotify\" to if it is running then play")
                    try? await Task.sleep(for: .milliseconds(400))
                    if let track = await fetchSpotifyCurrentlyPlaying() {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.currentTrack = track
                        }
                    }
                    return
                }
            }
            // Sinon chercher dans les playlists de l'utilisateur
            if let playlistURI = await fetchRandomSpotifyPlaylist(token: token) {
                let started = await startSpotifyPlaybackWithContext(contextURI: playlistURI, token: token)
                if started {
                    executeAppleScript("tell application \"Spotify\" to if it is running then play")
                    try? await Task.sleep(for: .milliseconds(400))
                    if let track = await fetchSpotifyCurrentlyPlaying() {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.currentTrack = track
                        }
                    }
                    return
                }
            }
        }

        // 2. Application Spotify locale sur macOS via AppleScript
        if let track = await playSpotifyLocalWithShuffle() {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.currentTrack = track
            }
            if track.artworkData == nil {
                resolveArtwork(for: track.title, artist: track.artist, album: track.album, fallbackURL: track.artworkURL)
            }
        }
    }

    private func fetchRandomSpotifySavedTrack(token: String) async -> String? {
        guard let url = URL(string: "https://api.spotify.com/v1/me/tracks?limit=50") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]], !items.isEmpty {
                let uris = items.compactMap { item -> String? in
                    (item["track"] as? [String: Any])?["uri"] as? String
                }
                return uris.randomElement()
            }
        } catch {
            return nil
        }
        return nil
    }

    private func fetchRandomSpotifyPlaylist(token: String) async -> String? {
        guard let url = URL(string: "https://api.spotify.com/v1/me/playlists?limit=25") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]], !items.isEmpty {
                let uris = items.compactMap { $0["uri"] as? String }
                return uris.randomElement()
            }
        } catch {
            return nil
        }
        return nil
    }

    private func startSpotifyPlaybackWithTrack(uri: String, token: String) async -> Bool {
        if let shuffleURL = URL(string: "https://api.spotify.com/v1/me/player/shuffle?state=true") {
            var shuffleReq = URLRequest(url: shuffleURL)
            shuffleReq.httpMethod = "PUT"
            shuffleReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: shuffleReq)
        }

        guard let playURL = URL(string: "https://api.spotify.com/v1/me/player/play") else { return false }
        var playReq = URLRequest(url: playURL)
        playReq.httpMethod = "PUT"
        playReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        playReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["uris": [uri]]
        playReq.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, resp) = try await URLSession.shared.data(for: playReq)
            if let http = resp as? HTTPURLResponse, (200...204).contains(http.statusCode) {
                return true
            }
        } catch {
            return false
        }
        return false
    }

    private func startSpotifyPlaybackWithContext(contextURI: String, token: String) async -> Bool {
        if let shuffleURL = URL(string: "https://api.spotify.com/v1/me/player/shuffle?state=true") {
            var shuffleReq = URLRequest(url: shuffleURL)
            shuffleReq.httpMethod = "PUT"
            shuffleReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: shuffleReq)
        }

        guard let playURL = URL(string: "https://api.spotify.com/v1/me/player/play") else { return false }
        var playReq = URLRequest(url: playURL)
        playReq.httpMethod = "PUT"
        playReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        playReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["context_uri": contextURI]
        playReq.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, resp) = try await URLSession.shared.data(for: playReq)
            if let http = resp as? HTTPURLResponse, (200...204).contains(http.statusCode) {
                return true
            }
        } catch {
            return false
        }
        return false
    }

    private func playSpotifyLocalWithShuffle() async -> NowPlayingTrack? {
        let scriptSource = """
        tell application "Spotify"
            if not running then
                launch
                delay 0.8
            end if
            try
                set shuffling to true
            end try
            try
                play track "spotify:collection:tracks"
            on error
                try
                    play
                end try
            end try
            delay 0.3
            try
                set pState to (player state as string)
                set trName to (name of current track as string)
                set trArtist to (artist of current track as string)
                set trAlbum to (album of current track as string)
                set trPos to (player position as string)
                set trDur to ((duration of current track) / 1000 as string)
                set trArt to (artwork url of current track as string)
                return pState & "|||" & trName & "|||" & trArtist & "|||" & trAlbum & "|||" & trPos & "|||" & trDur & "|||" & trArt
            on error
                return ""
            end try
        end tell
        """
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let script = NSAppleScript(source: scriptSource) else { return nil }
            var error: NSDictionary?
            return script.executeAndReturnError(&error).stringValue
        }.value

        guard let result, !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let isPlaying = parts[0] == "playing"
        let title = parts[1]
        let artist = parts[2]
        let album = parts[3]
        let elapsed = Self.parseDouble(parts[4]) ?? 0
        let duration = Self.parseDouble(parts[5]) ?? 210
        let artURL = (parts.count > 6 && !parts[6].isEmpty) ? URL(string: parts[6]) : nil
        guard !title.isEmpty else { return nil }

        let cacheKey = artworkCacheKey(title: title, artist: artist)
        let existingArtwork = artworkCache[cacheKey]

        return NowPlayingTrack(
            title: title,
            artist: artist,
            album: album,
            artworkURL: artURL,
            artworkData: existingArtwork,
            isPlaying: isPlaying,
            elapsedSeconds: elapsed,
            durationSeconds: max(1, duration),
            serviceSource: .spotify,
            canControlPlayback: true,
            limitationNotice: spotifyLimitationNotice
        )
    }

    // MARK: - Lecture Aléatoire Apple Music

    private func playRandomAppleMusicTrack() async {
        if let track = await playAppleMusicLocalWithShuffle() {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.currentTrack = track
            }
            if track.artworkData == nil {
                resolveArtwork(for: track.title, artist: track.artist, album: track.album)
            }
        }
    }

    private func playAppleMusicLocalWithShuffle() async -> NowPlayingTrack? {
        let scriptSource = """
        tell application "Music"
            if not running then
                launch
                delay 0.8
            end if
            try
                set shuffle enabled to true
            end try
            try
                set song_count to count of tracks of library playlist 1
                if song_count > 0 then
                    set random_idx to (random number from 1 to song_count)
                    play track random_idx of library playlist 1
                else
                    set pl_count to count of user playlists
                    if pl_count > 0 then
                        set random_pl_idx to (random number from 1 to pl_count)
                        play user playlist random_pl_idx
                    else
                        play
                    end if
                end if
            on error
                play
            end try
            delay 0.3
            try
                set pState to (player state as string)
                set trName to (name of current track as string)
                set trArtist to (artist of current track as string)
                set trAlbum to (album of current track as string)
                set trPos to (player position as string)
                set trDur to (duration of current track as string)
                return pState & "|||" & trName & "|||" & trArtist & "|||" & trAlbum & "|||" & trPos & "|||" & trDur
            on error
                return ""
            end try
        end tell
        """
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let script = NSAppleScript(source: scriptSource) else { return nil }
            var error: NSDictionary?
            return script.executeAndReturnError(&error).stringValue
        }.value

        guard let result, !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let isPlaying = parts[0] == "playing"
        let title = parts[1]
        let artist = parts[2]
        let album = parts[3]
        let elapsed = Self.parseDouble(parts[4]) ?? 0
        let duration = Self.parseDouble(parts[5]) ?? 240

        guard !title.isEmpty else { return nil }

        let cacheKey = artworkCacheKey(title: title, artist: artist)
        let existingArtwork = artworkCache[cacheKey]

        return NowPlayingTrack(
            title: title,
            artist: artist,
            album: album,
            artworkURL: nil,
            artworkData: existingArtwork,
            isPlaying: isPlaying,
            elapsedSeconds: elapsed,
            durationSeconds: max(1, duration),
            serviceSource: .appleMusic,
            canControlPlayback: true,
            limitationNotice: nil
        )
    }

    /// Exécute un script AppleScript hors du thread principal et indique s'il a abouti.
    /// On passe par `/usr/bin/osascript` (comme pour la lecture MediaRemote) : c'est plus
    /// fiable que `NSAppleScript` utilisé depuis une tâche détachée, et les erreurs
    /// d'autorisation Automation sont correctement remontées.
    @discardableResult
    private func runAppleScript(_ source: String) async -> Bool {
        let result = await Self.runOsascript(source)
        guard result.success else { return false }
        let output = result.output.lowercased()
        return output != "not-running" && output != "false"
    }

    /// Version « feu et oublie » pour les scripts dont le résultat n'a pas d'importance.
    private func executeAppleScript(_ source: String) {
        Task.detached(priority: .userInitiated) {
            _ = await Self.runOsascript(source)
        }
    }

    nonisolated private static func runOsascript(_ source: String) async -> (success: Bool, output: String) {
        await Task.detached(priority: .userInitiated) { () -> (Bool, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                return (false, "")
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = (String(data: errorData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus == 0, output.isEmpty ? errorOutput : output)
        }.value
    }

    // MARK: - Utilitaires PKCE

    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
