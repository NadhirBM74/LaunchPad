import Foundation
import AppKit
import ApplicationServices

// MARK: - Lecture système universelle (musique ET vidéo, toutes applications)
//
// macOS ne fournit aucune API publique pour lire le « Now Playing » global. Depuis macOS 15.4,
// le framework privé MediaRemote refuse les processus tiers. Il reste accessible aux binaires
// système d'Apple : on délègue donc la lecture et les commandes à `/usr/bin/osascript`
// (JavaScript for Automation), qui est signé par Apple. Rien n'est simulé : si aucune
// application ne publie de lecture, le résultat est simplement `nil`.

nonisolated struct SystemNowPlayingSnapshot: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var isPlaying: Bool
    var bundleID: String
    var appName: String
    var artworkData: Data?
}

nonisolated enum SystemMediaCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

nonisolated enum SystemNowPlayingClient {

    private static let readScript = """
    ObjC.import('Foundation');
    $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
    var R = $.NSClassFromString('MRNowPlayingRequest');
    var out = {};
    if (!R.isNil()) {
      var item = R.localNowPlayingItem;
      if (!item.isNil()) {
        var info = item.nowPlayingInfo;
        function s(k) { var v = info.objectForKey(k); return v.isNil() ? '' : String(ObjC.unwrap(v)); }
        function n(k) { var v = info.objectForKey(k); return v.isNil() ? 0 : Number(ObjC.unwrap(v)); }
        out.title = s('kMRMediaRemoteNowPlayingInfoTitle');
        out.artist = s('kMRMediaRemoteNowPlayingInfoArtist');
        out.album = s('kMRMediaRemoteNowPlayingInfoAlbum');
        out.duration = n('kMRMediaRemoteNowPlayingInfoDuration');
        out.elapsed = n('kMRMediaRemoteNowPlayingInfoElapsedTime');
        out.rate = n('kMRMediaRemoteNowPlayingInfoPlaybackRate');
        var ts = info.objectForKey('kMRMediaRemoteNowPlayingInfoTimestamp');
        out.timestamp = ts.isNil() ? 0 : Number(ts.timeIntervalSince1970);
        out.state = Number(R.localPlaybackState);
        var skipTitleObj = $.NSProcessInfo.processInfo.environment.objectForKey('LAUNCHPAD_SKIP_ARTWORK_TITLE');
        var skipTitle = skipTitleObj.isNil() ? '' : String(ObjC.unwrap(skipTitleObj));
        if (!skipTitle || out.title !== skipTitle) {
          var art = info.objectForKey('kMRMediaRemoteNowPlayingInfoArtworkData');
          if (!art.isNil()) { out.artwork = ObjC.unwrap(art.base64EncodedStringWithOptions(0)); }
        }
        try {
          var p = R.localNowPlayingPlayerPath;
          if (!p.isNil()) {
            out.bundle = ObjC.unwrap(p.client.bundleIdentifier) || '';
            out.app = ObjC.unwrap(p.client.displayName) || '';
          }
        } catch (e) {}
      }
    }
    JSON.stringify(out);
    """

    /// Lit la lecture système en cours. `nil` si rien n'est publié par une application.
    /// - Parameter skipArtworkForTitle: Si fourni et que le titre en cours correspond déjà à ce titre,
    ///   évite d'extraire et d'encoder en base64 la miniature MediaRemote à chaque cycle de polling.
    static func fetch(skipArtworkForTitle: String? = nil) async -> SystemNowPlayingSnapshot? {
        await Task.detached(priority: .utility) { () -> SystemNowPlayingSnapshot? in
            var env: [String: String]? = nil
            if let skipTitle = skipArtworkForTitle, !skipTitle.isEmpty {
                env = ["LAUNCHPAD_SKIP_ARTWORK_TITLE": skipTitle]
            }
            guard let data = runOsascript(script: readScript, extraEnvironment: env),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = json["title"] as? String else { return nil }

            let artist = (json["artist"] as? String) ?? ""
            guard !title.isEmpty || !artist.isEmpty else { return nil }

            let rate = (json["rate"] as? Double) ?? 0
            let state = (json["state"] as? Double) ?? 0
            // L'état publié par MediaRemote est plus fiable que le taux de lecture :
            // certains navigateurs laissent `rate` à 1 même en pause.
            let isPlaying: Bool
            switch Int(state) {
            case 1: isPlaying = true          // playing
            case 2, 3: isPlaying = false      // paused / stopped
            default: isPlaying = rate > 0     // unknown / interrupted → on se fie au taux
            }
            var elapsed = (json["elapsed"] as? Double) ?? 0
            let timestamp = (json["timestamp"] as? Double) ?? 0
            if isPlaying, timestamp > 0 {
                elapsed += max(0, Date().timeIntervalSince1970 - timestamp) * (rate > 0 ? rate : 1)
            }
            let duration = (json["duration"] as? Double) ?? 0
            if duration > 0 { elapsed = min(elapsed, duration) }

            let artwork = (json["artwork"] as? String).flatMap { Data(base64Encoded: $0) }

            return SystemNowPlayingSnapshot(
                title: title,
                artist: artist,
                album: (json["album"] as? String) ?? "",
                duration: duration,
                elapsed: max(0, elapsed),
                isPlaying: isPlaying,
                bundleID: (json["bundle"] as? String) ?? "",
                appName: (json["app"] as? String) ?? "",
                artworkData: (artwork?.isEmpty == false) ? artwork : nil
            )
        }.value
    }

    /// Envoie une commande de lecture à l'application qui publie actuellement la lecture.
    /// - Returns: `true` si MediaRemote a accepté la commande. Un résultat `false` permet
    ///   à l'appelant de basculer sur un contrôle direct de l'application (AppleScript).
    @discardableResult
    static func send(_ command: SystemMediaCommand) async -> Bool {
        let script = """
        ObjC.import('Foundation');
        $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
        ObjC.bindFunction('MRMediaRemoteSendCommand', ['bool', ['int', 'id']]);
        $.MRMediaRemoteSendCommand(\(command.rawValue), $());
        """
        return await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let data = runOsascript(script: script),
                  let text = String(data: data, encoding: .utf8) else { return false }
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("true") || normalized == "1"
        }.value
    }

    /// Déplace la lecture à `seconds` dans l'application source.
    /// - Returns: `true` si MediaRemote a accepté la commande.
    @discardableResult
    static func seek(to seconds: Double) async -> Bool {
        let script = """
        ObjC.import('Foundation');
        $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
        ObjC.bindFunction('MRMediaRemoteSendCommand', ['bool', ['int', 'id']]);
        $.MRMediaRemoteSendCommand(24, $({kMRMediaRemoteOptionPlaybackPosition: \(seconds)}));
        """
        return await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let data = runOsascript(script: script),
                  let text = String(data: data, encoding: .utf8) else { return false }
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("true") || normalized == "1"
        }.value
    }

    private static func runOsascript(script: String, extraEnvironment: [String: String]? = nil) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        if let extraEnvironment, !extraEnvironment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in extraEnvironment { env[k] = v }
            process.environment = env
        }
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Lecture avant waitUntilExit pour éviter tout blocage si le tampon du tube se remplit.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    /// Indique si l'application peut poster les touches multimédia matérielles.
    /// C'est le chemin de contrôle le plus universel : certains lecteurs (navigateurs
    /// notamment) publient leur état Now Playing mais ignorent `MRMediaRemoteSendCommand`.
    nonisolated static var canSendHardwareMediaKeys: Bool { AXIsProcessTrusted() }

    @MainActor
    private static var appIconCache: [String: NSImage] = [:]

    /// Icône de l'application source mise en cache mémoire (repli visuel quand aucune miniature n'est publiée).
    @MainActor
    static func appIcon(bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty else { return nil }
        if let cached = appIconCache[bundleID] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIconCache[bundleID] = icon
        return icon
    }
}

// MARK: - Touches multimédia matérielles (fallback universel)

/// Simule les touches « lecture/pause », « suivant » et « précédent » du clavier.
/// Ce chemin est indispensable pour les lecteurs qui répondent aux touches média
/// mais pas aux commandes MediaRemote (cas de certains navigateurs).
nonisolated enum SystemMediaKey {

    /// Codes `NX_KEYTYPE_*` du framework IOKit.
    private enum Key: Int32 {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    static func send(_ command: SystemMediaCommand) {
        switch command {
        case .togglePlayPause:
            post(.playPause)
        case .nextTrack:
            post(.next)
        case .previousTrack:
            post(.previous)
        case .play, .pause:
            // Aucune touche matérielle dédiée : ces commandes passent par MediaRemote.
            break
        }
    }

    private static func post(_ key: Key) {
        // Un appui média est un événement système composé d'un « down » puis d'un « up ».
        for isDown in [true, false] {
            let flags = isDown ? 0xA00 : 0xB00
            let data1 = (Int(key.rawValue) << 16) | flags
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
