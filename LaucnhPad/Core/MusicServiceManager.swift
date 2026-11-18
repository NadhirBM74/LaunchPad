import Foundation
import Combine
import SwiftUI
import AppKit
import CoreServices
import MusicKit
import AuthenticationServices
import CryptoKit
import Security
import ImageIO

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

@MainActor
public final class MusicProgressState: ObservableObject {
    @Published public var elapsedSeconds: Double = 0
}

public struct NowPlayingTrack: Equatable, @unchecked Sendable {
    nonisolated(unsafe) private static let sharedImageCache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    nonisolated private static func artworkDigest(for data: Data) -> Int {
        var hasher = Hasher()
        let count = data.count
        hasher.combine(count)
        if count <= 512 {
            hasher.combine(data)
        } else {
            let chunk = 64
            let step = (count - chunk) / 7
            for i in 0..<8 {
                let start = min(count - chunk, i * step)
                hasher.combine(data[start..<(start + chunk)])
            }
        }
        return hasher.finalize()
    }

    /// Décode (et rééchantillonne à <= 600 px) hors thread principal afin d'éviter tout blocage UI et économiser la RAM.
    @discardableResult
    nonisolated static func prewarmImageCache(for data: Data) -> NSImage? {
        guard !data.isEmpty else { return nil }
        let key = NSNumber(value: artworkDigest(for: data))
        if let existing = sharedImageCache.object(forKey: key) {
            return existing
        }
        let decoded: NSImage?
        if let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let pw = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let ph = props[kCGImagePropertyPixelHeight] as? CGFloat,
           max(pw, ph) > 600,
           let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: 600
           ] as CFDictionary) {
            decoded = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
        } else {
            decoded = NSImage(data: data)
        }
        guard let decoded else { return nil }
        let rep = decoded.representations.first
        let pixelCost = rep.map { max(1, $0.pixelsWide * $0.pixelsHigh * 4) } ?? max(1, data.count * 4)
        sharedImageCache.setObject(decoded, forKey: key, cost: pixelCost)
        return decoded
    }

    private static func cachedImage(for data: Data?) -> NSImage? {
        guard let data, !data.isEmpty else { return nil }
        return prewarmImageCache(for: data)
    }

    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var artworkData: Data? {
        didSet {
            let newCount = artworkData?.count ?? 0
            let newHash = artworkData.map { Self.artworkDigest(for: $0) } ?? 0
            if newCount != _artworkByteCount || newHash != _artworkHash {
                _artworkByteCount = newCount
                _artworkHash = newHash
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
    private var _artworkByteCount: Int = 0
    private var _artworkHash: Int = 0

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
        self._artworkByteCount = artworkData?.count ?? 0
        self._artworkHash = artworkData.map { Self.artworkDigest(for: $0) } ?? 0
        self._cachedImage = Self.cachedImage(for: artworkData)
    }

    public static func == (lhs: NowPlayingTrack, rhs: NowPlayingTrack) -> Bool {
        let sameArtwork: Bool
        if let lImg = lhs._cachedImage, let rImg = rhs._cachedImage, lImg === rImg {
            sameArtwork = true
        } else {
            sameArtwork = (lhs._artworkByteCount == rhs._artworkByteCount) && (lhs._artworkHash == rhs._artworkHash)
        }
        return lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.artworkURL == rhs.artworkURL &&
        sameArtwork &&
        lhs.isPlaying == rhs.isPlaying &&
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

nonisolated enum KeychainHelper {
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
    public let progressState = MusicProgressState()
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
    private var failedArtworkQueries: [String: TimeInterval] = [:]
    private var inFlightArtworkQueries: Set<String> = []
    private var inFlightSpotifyRefreshTask: Task<String?, Never>?
    private var spotifyNotificationRefreshTask: Task<Void, Never>?
    private var scheduledRefreshTask: Task<Void, Never>?
    private var randomLaunchTask: Task<Void, Never>?
    private var isRefreshingNowPlaying = false
    private var lastRefreshUptime: TimeInterval = 0
    private var lastSystemFetchUptime: TimeInterval = 0
    private var cachedSystemTrack: NowPlayingTrack? = nil
    private var hasPendingNotificationUpdate = false
    private var isLaunchpadCurrentlyVisible: Bool = LaunchpadViewModel.isLaunchpadVisible
    private var activeWidgetObserverCount: Int = 0
    private var cachedSpotifyInstalled: (value: Bool, uptime: TimeInterval)?
    private var cachedAppleMusicInstalled: (value: Bool, uptime: TimeInterval)?

    public var isSpotifyInstalled: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = cachedSpotifyInstalled, (now - cached.uptime) < 60.0 {
            return cached.value
        }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
        cachedSpotifyInstalled = (installed, now)
        return installed
    }

    public var isAppleMusicInstalled: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = cachedAppleMusicInstalled, (now - cached.uptime) < 60.0 {
            return cached.value
        }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") != nil
        cachedAppleMusicInstalled = (installed, now)
        return installed
    }

    public func beginObserving() {
        activeWidgetObserverCount += 1
        if activeWidgetObserverCount == 1 && isLaunchpadCurrentlyVisible {
            refreshNowPlaying(force: true)
            startPolling()
        }
    }

    public func endObserving() {
        activeWidgetObserverCount = max(0, activeWidgetObserverCount - 1)
        if activeWidgetObserverCount == 0 {
            stopPolling()
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

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

            if UserDefaults.standard.bool(forKey: "AppleMusicConnected") || MusicAuthorization.currentStatus == .authorized {
                self.verifyAppleMusicAuthorization()
            }

            await self.verifyNativeSpotifyAvailability(askUserIfNeeded: false)

            if self.isLaunchpadCurrentlyVisible && self.activeWidgetObserverCount > 0 {
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
        dnc.addObserver(
            self,
            selector: #selector(handleAppleMusicNotification(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dnc.addObserver(
            self,
            selector: #selector(handleSpotifyNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLaunchpadVisibilityChanged(_:)),
            name: .launchpadVisibilityDidChange,
            object: nil
        )
    }

    @objc private func handleLaunchpadVisibilityChanged(_ notif: Notification) {
        guard let isVisible = notif.object as? Bool else { return }
        self.isLaunchpadCurrentlyVisible = isVisible
        if isVisible {
            self.hasPendingNotificationUpdate = false
            if self.activeWidgetObserverCount > 0 {
                self.refreshNowPlaying(force: true)
                self.startPolling()
            }
        } else {
            self.stopPolling()
        }
    }

    @objc private func handleAppleMusicNotification(_ notif: Notification) {
        guard let info = notif.userInfo, activeWidgetObserverCount > 0 else { return }
        if !isLaunchpadCurrentlyVisible {
            hasPendingNotificationUpdate = true
            return
        }
        processAppleMusicNotification(info: info)
    }

    private func processAppleMusicNotification(info: [AnyHashable: Any]) {
        if preferredService == .spotify { return }
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
            let elapsed = isSameSong ? self.progressState.elapsedSeconds : 0

            assignCurrentTrack(NowPlayingTrack(
                title: name,
                artist: artist,
                album: album,
                artworkURL: nil,
                artworkData: existingArtwork,
                isPlaying: isPlaying,
                elapsedSeconds: elapsed,
                durationSeconds: totalTimeSec > 0 ? totalTimeSec : (isSameSong ? self.currentTrack.durationSeconds : 240),
                serviceSource: .appleMusic,
                canControlPlayback: true,
                limitationNotice: nil
            ))
        }
    }

    @objc private func handleSpotifyNotification(_ notif: Notification) {
        guard let info = notif.userInfo, activeWidgetObserverCount > 0 else { return }
        if !isLaunchpadCurrentlyVisible {
            hasPendingNotificationUpdate = true
            return
        }
        processSpotifyNotification(info: info)
    }

    private func processSpotifyNotification(info: [AnyHashable: Any]) {
        let playerState = ((info["Player State"] as? String) ?? "").lowercased()
        let isPlaying = playerState == "playing"
        let name = ((info["Name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = ((info["Artist"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let album = ((info["Album"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDuration = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        let durationSec = rawDuration > 1000 ? (rawDuration / 1000.0) : rawDuration
        let notifElapsed = (info["Playback Position"] as? NSNumber)?.doubleValue

        if playerState == "stopped" || name.isEmpty {
            if preferredService == .spotify || currentTrack.serviceSource == .spotify {
                assignCurrentTrack(.empty)
            }
            return
        }

        // Si l'utilisateur a verrouillé Apple Music, ignorer les notifications Spotify en arrière-plan.
        if preferredService == .appleMusic { return }

        if spotifyStatus == .notConnected && isSpotifyInstalled {
            spotifyStatus = .connected(details: "Spotify macOS")
        }

        let isSameSong = (self.currentTrack.title == name && self.currentTrack.artist == artist && self.currentTrack.serviceSource == .spotify)
        let cacheKey = artworkCacheKey(title: name, artist: artist)
        let existingArtwork = isSameSong ? self.currentTrack.artworkData : artworkCache[cacheKey]
        let elapsed = notifElapsed ?? (isSameSong ? self.progressState.elapsedSeconds : 0)
        let resolvedDuration = durationSec > 0 ? durationSec : (isSameSong && self.currentTrack.durationSeconds > 0 ? self.currentTrack.durationSeconds : 210)

        assignCurrentTrack(NowPlayingTrack(
            title: name,
            artist: artist,
            album: album,
            artworkURL: isSameSong ? self.currentTrack.artworkURL : nil,
            artworkData: existingArtwork,
            isPlaying: isPlaying,
            elapsedSeconds: elapsed,
            durationSeconds: resolvedDuration,
            serviceSource: .spotify,
            canControlPlayback: true,
            limitationNotice: nil
        ))

        if existingArtwork == nil, isLaunchpadCurrentlyVisible {
            // Récupère immédiatement l'URL officielle de pochette depuis Spotify Desktop (i.scdn.co) sans attendre le timer de 10 s.
            spotifyNotificationRefreshTask?.cancel()
            spotifyNotificationRefreshTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, self.isLaunchpadCurrentlyVisible else { return }
                if let local = await self.fetchLocalSpotifyTrack() {
                    self.assignCurrentTrack(local)
                }
            }
        }
    }

    private func startPolling() {
        guard isLaunchpadCurrentlyVisible && activeWidgetObserverCount > 0 else { return }
        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isLaunchpadCurrentlyVisible, self.activeWidgetObserverCount > 0 else { return }
                self.refreshNowPlaying()
            }
        }
        newTimer.tolerance = 2.5
        timer = newTimer
        updateProgressTimerState()
    }

    private func updateProgressTimerState() {
        let needsTick = isLaunchpadCurrentlyVisible && activeWidgetObserverCount > 0 && currentTrack.isPlaying && currentTrack.hasTrack && currentTrack.durationSeconds > 0
        if needsTick {
            guard progressTimer == nil else { return }
            lastProgressTickUptime = ProcessInfo.processInfo.systemUptime
            let newProgressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isLaunchpadCurrentlyVisible, self.activeWidgetObserverCount > 0,
                          self.currentTrack.isPlaying, self.currentTrack.hasTrack, self.currentTrack.durationSeconds > 0 else {
                        self?.progressTimer?.invalidate()
                        self?.progressTimer = nil
                        return
                    }
                    let now = ProcessInfo.processInfo.systemUptime
                    let delta = max(0, min(4.0, now - self.lastProgressTickUptime))
                    self.lastProgressTickUptime = now
                    let nextElapsed = min(self.currentTrack.durationSeconds, self.progressState.elapsedSeconds + delta)
                    if Int(nextElapsed.rounded()) != Int(self.progressState.elapsedSeconds.rounded()) {
                        self.progressState.elapsedSeconds = nextElapsed
                    }
                }
            }
            newProgressTimer.tolerance = 0.5
            progressTimer = newProgressTimer
        } else {
            progressTimer?.invalidate()
            progressTimer = nil
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        spotifyNotificationRefreshTask?.cancel()
        spotifyNotificationRefreshTask = nil
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        randomLaunchTask?.cancel()
        randomLaunchTask = nil
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

    // MARK: - Source & Connexion Native Spotify (sans configuration développeur)

    /// Sélectionne la source audio dans les Réglages et connecte le service choisi en 1 clic.
    public func selectSource(_ source: MusicServiceSource) {
        preferredService = source
        switch source {
        case .spotify:
            if !spotifyStatus.isConnected {
                connectSpotify()
            } else {
                refreshNowPlaying(force: true)
            }
        case .appleMusic:
            if !appleMusicStatus.isConnected {
                connectAppleMusic()
            } else {
                refreshNowPlaying(force: true)
            }
        case .system, .none:
            refreshNowPlaying(force: true)
        }
    }

    public func openAutomationPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated private static func checkAutomationPermission(bundleID: String, askUserIfNeeded: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let aeDesc = target.aeDesc else { return OSStatus(-1) }
        return AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, askUserIfNeeded)
    }

    private func verifyNativeSpotifyAvailability(askUserIfNeeded: Bool) async {
        guard isSpotifyInstalled else {
            spotifyStatus = .notConnected
            return
        }

        let status = await Task.detached(priority: .utility) {
            Self.checkAutomationPermission(bundleID: "com.spotify.client", askUserIfNeeded: askUserIfNeeded)
        }.value

        switch status {
        case noErr:
            UserDefaults.standard.set(true, forKey: "SpotifyLocalConnected")
            spotifyUserDisplayName = nil
            spotifyLimitationNotice = nil
            spotifyStatus = .connected(details: "Spotify macOS")
        case OSStatus(errAEEventNotPermitted):
            spotifyStatus = .restricted(reason: loc("music.spotify.auth_required"))
        default:
            if UserDefaults.standard.bool(forKey: "SpotifyLocalConnected") {
                spotifyStatus = .connected(details: "Spotify macOS")
            } else {
                spotifyStatus = .notConnected
            }
        }
    }

    /// Connecte Spotify nativement sur macOS sans compte développeur ni navigateur OAuth.
    public func connectSpotify() {
        guard let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            self.spotifyStatus = .error(message: loc("music.spotify.not_installed"))
            return
        }

        self.spotifyStatus = .connecting
        self.spotifyLimitationNotice = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            var permStatus = await Task.detached(priority: .userInitiated) {
                Self.checkAutomationPermission(bundleID: "com.spotify.client", askUserIfNeeded: true)
            }.value

            // Si Spotify n'est pas encore ouvert (procNotFound = -600), l'ouvrir discrètement en arrière-plan
            // afin que macOS puisse afficher une seule fois la demande d'autorisation native.
            if permStatus == OSStatus(procNotFound) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.hides = true
                _ = try? await NSWorkspace.shared.openApplication(at: spotifyURL, configuration: config)

                for _ in 0..<10 {
                    if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                try? await Task.sleep(for: .milliseconds(250))

                permStatus = await Task.detached(priority: .userInitiated) {
                    Self.checkAutomationPermission(bundleID: "com.spotify.client", askUserIfNeeded: true)
                }.value
            }

            switch permStatus {
            case noErr:
                UserDefaults.standard.set(true, forKey: "SpotifyLocalConnected")
                self.spotifyStatus = .connected(details: "Spotify macOS")
                self.refreshNowPlaying(force: true)
            case OSStatus(errAEEventNotPermitted):
                UserDefaults.standard.set(false, forKey: "SpotifyLocalConnected")
                self.spotifyStatus = .restricted(reason: loc("music.spotify.automation_denied"))
            default:
                // Dernier essai direct via AppleScript si Spotify démarre encore
                let res = await Self.runOsascript("tell application \"Spotify\" to get player state")
                if res.success {
                    UserDefaults.standard.set(true, forKey: "SpotifyLocalConnected")
                    self.spotifyStatus = .connected(details: "Spotify macOS")
                    self.refreshNowPlaying(force: true)
                } else {
                    UserDefaults.standard.set(true, forKey: "SpotifyLocalConnected")
                    self.spotifyStatus = .connected(details: loc("music.spotify.ready_mac"))
                    self.refreshNowPlaying(force: true)
                }
            }
        }
    }

    public func disconnectSpotify() {
        KeychainHelper.delete(key: "spotify_access_token")
        KeychainHelper.delete(key: "spotify_refresh_token")
        KeychainHelper.delete(key: "spotify_token_expiry")
        UserDefaults.standard.removeObject(forKey: "SpotifyUserDisplayName")
        UserDefaults.standard.removeObject(forKey: "SpotifyProductType")
        UserDefaults.standard.set(false, forKey: "SpotifyLocalConnected")

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
                let errString = String(data: data, encoding: .utf8) ?? loc("music.err.unknown")
                self.spotifyStatus = .error(message: loc("music.err.token_exchange", errString))
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
        if let existingTask = inFlightSpotifyRefreshTask {
            return await existingTask.value
        }
        let clientID = effectiveSpotifyClientID
        let task = Task<String?, Never> {
            let credentials = await Task.detached(priority: .utility) {
                (
                    expiry: KeychainHelper.loadString(key: "spotify_token_expiry").flatMap(Double.init),
                    refresh: KeychainHelper.loadString(key: "spotify_refresh_token"),
                    access: KeychainHelper.loadString(key: "spotify_access_token")
                )
            }.value

            guard let expiryTimestamp = credentials.expiry,
                  let refreshToken = credentials.refresh else {
                return credentials.access
            }

            if Date().timeIntervalSince1970 < (expiryTimestamp - 60) {
                return credentials.access
            }

            guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let bodyParams = [
                "grant_type": "refresh_token",
                "client_id": clientID,
                "refresh_token": refreshToken
            ]
            request.httpBody = bodyParams
                .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
                .joined(separator: "&")
                .data(using: .utf8)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode == 400 || statusCode == 401 {
                    await MainActor.run { [weak self] in
                        self?.spotifyStatus = .notConnected
                    }
                    return nil
                }
                guard statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let newAccessToken = json["access_token"] as? String else {
                    return nil
                }

                let expiresIn = json["expires_in"] as? Double
                let newRefresh = json["refresh_token"] as? String
                await Task.detached(priority: .utility) {
                    KeychainHelper.saveString(key: "spotify_access_token", value: newAccessToken)
                    if let expiresIn {
                        let expiryDate = Date().addingTimeInterval(expiresIn)
                        KeychainHelper.saveString(key: "spotify_token_expiry", value: String(expiryDate.timeIntervalSince1970))
                    }
                    if let newRefresh {
                        KeychainHelper.saveString(key: "spotify_refresh_token", value: newRefresh)
                    }
                }.value
                return newAccessToken
            } catch {
                return nil
            }
        }
        inFlightSpotifyRefreshTask = task
        let result = await task.value
        inFlightSpotifyRefreshTask = nil
        return result
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
            self.spotifyStatus = .connected(details: loc("music.status.connected"))
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
        if Int(progressState.elapsedSeconds.rounded()) != Int(newTrack.elapsedSeconds.rounded()) {
            progressState.elapsedSeconds = newTrack.elapsedSeconds
        }
        updateProgressTimerState()

        if newTrack.hasTrack && newTrack.artworkData == nil && isLaunchpadCurrentlyVisible {
            switch newTrack.serviceSource {
            case .spotify:
                resolveArtwork(for: newTrack.title, artist: newTrack.artist, album: newTrack.album, fallbackURL: newTrack.artworkURL, allowLocalMusicApp: false)
            case .appleMusic:
                resolveArtwork(for: newTrack.title, artist: newTrack.artist, album: newTrack.album, allowLocalMusicApp: true)
            case .system:
                if !Self.isBrowser(bundleID: newTrack.sourceBundleID), !newTrack.artist.isEmpty {
                    resolveArtwork(for: newTrack.title, artist: newTrack.artist, album: newTrack.album, allowLocalMusicApp: false)
                }
            case .none:
                break
            }
        }
    }

    private func performRefreshNowPlaying(force: Bool = false) async {
        // 1. Source explicite Spotify : 100 % native sur Spotify macOS sans basculer sur un autre lecteur.
        if preferredService == .spotify {
            if let localSpotify = await fetchLocalSpotifyTrack() {
                assignCurrentTrack(localSpotify)
                return
            }
            let hasToken = await Task.detached(priority: .utility) {
                KeychainHelper.loadString(key: "spotify_access_token") != nil
            }.value
            if hasToken, let tokenTrack = await fetchSpotifyCurrentlyPlaying() {
                assignCurrentTrack(tokenTrack)
                return
            }
            if currentTrack.hasTrack {
                assignCurrentTrack(.empty)
            }
            return
        }

        // 2. Source explicite Apple Music : reste strictement dédiée à l'app Musique.
        if preferredService == .appleMusic {
            if let track = await fetchLocalAppleMusicTrack() {
                assignCurrentTrack(track)
                return
            }
            if currentTrack.hasTrack {
                assignCurrentTrack(.empty)
            }
            return
        }

        // 3. Mode Automatique (.system) : détecte d'abord Spotify / Musique s'ils sont ouverts.
        async let localAppleTrack = fetchLocalAppleMusicTrack()
        async let localSpotifyTrack = fetchLocalSpotifyTrack()

        let (localApple, localSpotify) = await (localAppleTrack, localSpotifyTrack)
        let dedicatedCandidates = [localSpotify, localApple].compactMap { $0 }

        if let playingDedicated = dedicatedCandidates.first(where: { $0.isPlaying }) {
            assignCurrentTrack(playingDedicated)
            return
        }

        // 4. Sinon interroger les navigateurs / lecteurs vidéo / médias système via MediaRemote.
        let system = await fetchSystemTrack(force: force)
        let candidates = dedicatedCandidates + [system].compactMap { $0 }

        if let playingCandidate = candidates.first(where: { $0.isPlaying }) {
            assignCurrentTrack(playingCandidate)
            return
        }

        if let pausedCandidate = candidates.first(where: { $0.hasTrack }) {
            assignCurrentTrack(pausedCandidate)
            return
        }

        if currentTrack.hasTrack {
            assignCurrentTrack(.empty)
        }
    }

    // MARK: - Lecture système universelle (navigateurs, VLC, lecteurs vidéo…)

    private func fetchSystemTrack(force: Bool = false) async -> NowPlayingTrack? {
        let now = ProcessInfo.processInfo.systemUptime
        if !force, (now - lastSystemFetchUptime) < 8.5 {
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
            if self.currentTrack.title == trimmedTitle &&
               (trimmedArtist.isEmpty || self.currentTrack.artist.caseInsensitiveCompare(trimmedArtist) == .orderedSame) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.currentTrack.artworkData = cachedData
                }
            }
            return
        }

        // Éviter de réessayer pendant 10 minutes si la recherche de pochette a déjà échoué
        let now = ProcessInfo.processInfo.systemUptime
        if let failedAt = failedArtworkQueries[cacheKey] {
            if (now - failedAt) < 600.0 && fallbackURL == nil {
                return
            }
            failedArtworkQueries.removeValue(forKey: cacheKey)
        }

        // Éviter les requêtes concurrentes en doublon pour le même morceau
        if inFlightArtworkQueries.contains(cacheKey) { return }
        inFlightArtworkQueries.insert(cacheKey)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.inFlightArtworkQueries.remove(cacheKey)
            }

            @MainActor
            func applyIfStillCurrent(_ data: Data) {
                self.failedArtworkQueries.removeValue(forKey: cacheKey)
                self.storeArtwork(data, forKey: cacheKey)
                let curTitle = self.currentTrack.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if curTitle.caseInsensitiveCompare(trimmedTitle) == .orderedSame {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.currentTrack.artworkData = data
                    }
                }
            }

            // Étape A : Télécharger depuis le fallbackURL (ex: Spotify CDN) si présent
            if let fallbackURL, let data = await self.fetchArtworkData(from: fallbackURL) {
                applyIfStillCurrent(data)
                return
            }

            // Étape B : Extraction de la pochette locale via osascript hors du thread principal
            let localData: Data? = allowLocalMusicApp ? await Task.detached(priority: .userInitiated) {
                Self.extractLocalMusicArtwork()
            }.value : nil

            if let localData, !localData.isEmpty {
                let decoded = await Task.detached(priority: .userInitiated) {
                    NowPlayingTrack.prewarmImageCache(for: localData) != nil
                }.value
                if decoded {
                    applyIfStillCurrent(localData)
                    return
                }
            }

            // Étape C : Requête sur l'API officielle iTunes Search (Apple CDN, cover HD 600x600)
            if let remoteData = await self.searchArtworkOnITunes(title: trimmedTitle, artist: trimmedArtist) {
                applyIfStillCurrent(remoteData)
                return
            }

            if self.failedArtworkQueries.count >= 64 {
                let oldestKeys = Array(self.failedArtworkQueries.keys.prefix(32))
                for k in oldestKeys { self.failedArtworkQueries.removeValue(forKey: k) }
            }
            self.failedArtworkQueries[cacheKey] = ProcessInfo.processInfo.systemUptime
        }
    }

    nonisolated private static let featRegex = try? NSRegularExpression(pattern: #"\s*[\(\[]feat[^\)\]]*[\)\]]"#, options: [.caseInsensitive])
    nonisolated private static let ftRegex = try? NSRegularExpression(pattern: #"\s*[\(\[]ft[^\)\]]*[\)\]]"#, options: [.caseInsensitive])

    nonisolated private static func stripFeaturing(_ text: String) -> String {
        var working = text
        if let r1 = featRegex {
            working = r1.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        if let r2 = ftRegex {
            working = r2.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchArtworkOnITunes(title: String, artist: String) async -> Data? {
        let cleanTitle = Self.stripFeaturing(title)
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
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp_artwork_\(UUID().uuidString).dat")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let escapedPath = tempFile.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        if application "Music" is running then
            tell application "Music"
                try
                    if exists (artwork 1 of current track) then
                        set rawData to raw data of artwork 1 of current track
                        set fRef to open for access POSIX file "\(escapedPath)" with write permission
                        set eof of fRef to 0
                        write rawData to fRef
                        close access fRef
                        return "ok"
                    end if
                on error
                    try
                        close access POSIX file "\(escapedPath)"
                    end try
                end try
            end tell
        end if
        return ""
        """
        let result = runOsascriptSync(scriptSource, timeoutSeconds: 5.0)
        guard result.success, result.output == "ok",
              let data = try? Data(contentsOf: tempFile), !data.isEmpty else {
            return nil
        }
        return data
    }

    private func fetchArtworkData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              !data.isEmpty else {
            return nil
        }
        let valid = await Task.detached(priority: .userInitiated) {
            NowPlayingTrack.prewarmImageCache(for: data) != nil
        }.value
        return valid ? data : nil
    }

    private static func parseDouble(_ string: String) -> Double? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    nonisolated private static let appleMusicQueryScriptSource = """
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

    nonisolated private static let spotifyQueryScriptSource = """
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

    nonisolated private static func executeCachedAppleMusicQuery() -> String? {
        let res = runOsascriptSync(appleMusicQueryScriptSource, timeoutSeconds: 4.0)
        return res.success && !res.output.isEmpty ? res.output : nil
    }

    nonisolated private static func executeCachedSpotifyQuery() -> String? {
        let res = runOsascriptSync(spotifyQueryScriptSource, timeoutSeconds: 4.0)
        return res.success && !res.output.isEmpty ? res.output : nil
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

        return NowPlayingTrack(
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
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = Self.parseDouble(parts[4]) ?? 0
        let duration = Self.parseDouble(parts[5]) ?? 210
        let artworkUrlString = parts.count > 6 ? parts[6].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        guard !title.isEmpty else { return nil }

        let artURL = artworkUrlString.isEmpty ? nil : URL(string: artworkUrlString)
        let isSameSong = (self.currentTrack.title == title && self.currentTrack.artist == artist && self.currentTrack.serviceSource == .spotify)
        let cacheKey = artworkCacheKey(title: title, artist: artist)
        let existingArtwork = isSameSong ? self.currentTrack.artworkData : artworkCache[cacheKey]

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
            limitationNotice: nil
        )
    }

    // MARK: - Contrôles de Lecture (Play / Pause / Next / Prev)

    /// Déplace la lecture à une position (0…1) de la durée du morceau en cours.
    public func seek(toFraction fraction: Double) {
        let track = currentTrack
        guard track.hasTrack, track.durationSeconds > 0 else { return }
        let seconds = min(track.durationSeconds, max(0, fraction * track.durationSeconds))
        currentTrack.elapsedSeconds = seconds
        progressState.elapsedSeconds = seconds
        lastProgressTickUptime = ProcessInfo.processInfo.systemUptime

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
                if !done {
                    if self.spotifyStatus.isConnected && self.spotifyProductType?.lowercased() == "premium",
                       let token = await self.refreshSpotifyTokenIfNeeded(),
                       let url = URL(string: "https://api.spotify.com/v1/me/player/seek?position_ms=\(Int(seconds * 1000))") {
                        var request = URLRequest(url: url)
                        request.httpMethod = "PUT"
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        _ = try? await URLSession.shared.data(for: request)
                    } else {
                        _ = await SystemNowPlayingClient.seek(to: seconds)
                    }
                }
            case .none:
                break
            }
            self.scheduleRefresh([0.5, 1.2])
        }
    }

    private func scheduleRefresh(_ delays: [Double]) {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { @MainActor [weak self] in
            var previousDelay: Double = 0
            for delay in delays {
                let delta = max(0, delay - previousDelay)
                previousDelay = delay
                try? await Task.sleep(for: .milliseconds(Int(delta * 1000)))
                guard !Task.isCancelled, let self, self.isLaunchpadCurrentlyVisible else { return }
                self.refreshNowPlaying(force: true)
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

    public var preferredConnectedPlatformName: String {
        if preferredService == .spotify || (preferredService == .system && spotifyStatus.isConnected && !appleMusicStatus.isConnected) {
            return "Spotify"
        }
        if preferredService == .appleMusic || appleMusicStatus.isConnected {
            return "Apple Music"
        }
        return loc("music.apple.default_name")
    }

    /// Lance et démarre la lecture sur la plateforme musicale connectée (Spotify ou Apple Music).
    public func launchAndPlayPreferredPlatform() {
        let useSpotify = (preferredService == .spotify) || (preferredService == .system && spotifyStatus.isConnected && !appleMusicStatus.isConnected)
        if useSpotify {
            playRandomMusic()
        } else {
            let bundleID = "com.apple.Music"
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.toggleAppleMusicPlayback()
                self?.refreshNowPlaying()
            }
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
        updateProgressTimerState()
        let shouldPlay = currentTrack.isPlaying

        Task { @MainActor [weak self] in
            guard let self else { return }
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
            if !done {
                if self.spotifyStatus.isConnected && self.spotifyProductType?.lowercased() == "premium",
                   let token = await self.refreshSpotifyTokenIfNeeded(),
                   let url = URL(string: "https://api.spotify.com/v1/me/player/\(shouldPlay ? "play" : "pause")") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "PUT"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    _ = try? await URLSession.shared.data(for: request)
                } else {
                    await self.sendFallbackCommand(.togglePlayPause)
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
            if !done {
                if self.spotifyStatus.isConnected && self.spotifyProductType?.lowercased() == "premium",
                   let token = await self.refreshSpotifyTokenIfNeeded(),
                   let url = URL(string: "https://api.spotify.com/v1/me/player/next") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    _ = try? await URLSession.shared.data(for: request)
                } else {
                    await self.sendFallbackCommand(.nextTrack)
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
            if !done {
                if self.spotifyStatus.isConnected && self.spotifyProductType?.lowercased() == "premium",
                   let token = await self.refreshSpotifyTokenIfNeeded(),
                   let url = URL(string: "https://api.spotify.com/v1/me/player/previous") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    _ = try? await URLSession.shared.data(for: request)
                } else {
                    await self.sendFallbackCommand(.previousTrack)
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
        randomLaunchTask?.cancel()
        randomLaunchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLaunchingRandomTrack = true
            defer {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, !Task.isCancelled else { return }
                    self.isLaunchingRandomTrack = false
                }
            }

            let service = self.determineTargetMusicService()
            switch service {
            case .spotify:
                await self.playRandomSpotifyTrack()
            case .appleMusic, .system, .none:
                await self.playRandomAppleMusicTrack()
            }

            for delayMs in [400, 900, 1600, 2400] {
                try? await Task.sleep(for: .milliseconds(delayMs == 400 ? 400 : 550))
                if Task.isCancelled { break }
                self.refreshNowPlaying(force: true)
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
                            self.assignCurrentTrack(track)
                        }
                    }
                    return
                }
            }
        }

        // 2. Application Spotify locale sur macOS via AppleScript
        if let track = await playSpotifyLocalWithShuffle() {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.assignCurrentTrack(track)
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
        if !isAppRunning(bundleID: "com.spotify.client"),
           let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: spotifyURL, configuration: cfg)
            for _ in 0..<12 {
                if isAppRunning(bundleID: "com.spotify.client") { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            try? await Task.sleep(for: .milliseconds(400))
        }

        let scriptSource = """
        tell application "Spotify"
            if not running then
                launch
                delay 1.0
            end if
            try
                set shuffling to true
            end try
            try
                play
            end try
            delay 0.35
            try
                if (player state as string) is not "playing" then
                    try
                        play track "spotify:collection:tracks"
                        delay 0.35
                    end try
                end if
            end try
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
        let result = await Self.runOsascript(scriptSource).output
        let resolvedResult: String? = result.isEmpty ? nil : result

        guard let result = resolvedResult, !result.isEmpty else { return nil }
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
                self.assignCurrentTrack(track)
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
        let result = await Self.runOsascript(scriptSource).output
        let resolvedResult: String? = result.isEmpty ? nil : result

        guard let result = resolvedResult, !result.isEmpty else { return nil }
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

    nonisolated private static func runOsascriptSync(_ source: String, timeoutSeconds: TimeInterval = 6.0) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let timeoutWorkItem = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)
        defer { timeoutWorkItem.cancel() }

        do {
            try process.run()
        } catch {
            return (false, "")
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus == 0, output)
    }

    nonisolated private static func runOsascript(_ source: String) async -> (success: Bool, output: String) {
        await Task.detached(priority: .userInitiated) {
            runOsascriptSync(source)
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
