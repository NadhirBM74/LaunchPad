import AppKit
import CoreServices
import ImageIO
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

// MARK: - Modèle d'application

nonisolated struct AppInfo: Identifiable, Hashable, Sendable {
    /// Chemin standardisé (non résolu) — identifiant stable dans la disposition.
    let id: String
    let url: URL
    /// Chemin résolu (les liens symboliques comme /Applications/Safari.app pointent vers le cryptex système).
    let resolvedPath: String
    let name: String
    let normalizedName: String
    let bundleID: String?
    let normalizedBundleID: String?
    let category: String?
    let dateAdded: Date?
    let lastUsed: Date?
    let bundleModTime: TimeInterval

    init(
        id: String,
        url: URL,
        resolvedPath: String,
        name: String,
        bundleID: String?,
        category: String?,
        dateAdded: Date?,
        lastUsed: Date?,
        bundleModTime: TimeInterval = 0
    ) {
        self.id = id
        self.url = url
        self.resolvedPath = resolvedPath
        self.name = name
        self.normalizedName = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        self.bundleID = bundleID
        self.normalizedBundleID = bundleID?.lowercased()
        self.category = category
        self.dateAdded = dateAdded
        self.lastUsed = lastUsed
        self.bundleModTime = bundleModTime
    }

    var isSystem: Bool { resolvedPath.hasPrefix("/System/") }
    var isRemovable: Bool { !isSystem && bundleID != Bundle.main.bundleIdentifier }

    /// Clé de catégorie normalisée (« productivity », « games »…).
    var categoryKey: String? {
        guard let category, category.hasPrefix("public.app-category.") else { return nil }
        let key = String(category.dropFirst("public.app-category.".count))
        return key.hasSuffix("-games") ? "games" : key
    }
}

// MARK: - Analyse des dossiers d'applications

nonisolated enum AppScanner {
    static let defaultSources: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "~/Applications",
    ]

    private static let infoCacheLock = NSLock()
    nonisolated(unsafe) private static var cachedScanEntries: [String: (modTime: TimeInterval, info: AppInfo)] = [:]

    static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    static func scan(sources: [String]) -> [AppInfo] {
        let manager = FileManager.default
        let ownBundleID = Bundle.main.bundleIdentifier
        var seenPaths = Set<String>()
        var seenBundles = Set<String>()
        var visitedDirs = Set<String>()
        var result: [AppInfo] = []

        func visit(_ directory: URL, depth: Int) {
            let stdDirPath = directory.standardizedFileURL.path
            guard visitedDirs.insert(stdDirPath).inserted else { return }
            guard let entries = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .addedToDirectoryDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if entry.pathExtension.lowercased() == "app" {
                    let resolved = entry.resolvingSymlinksInPath().standardizedFileURL.path
                    guard seenPaths.insert(resolved).inserted else { continue }
                    let rValues = try? entry.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
                    let modTime = rValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
                    guard let info = makeInfo(entry, resolvedPath: resolved, addedDate: rValues?.addedToDirectoryDate, modTime: modTime) else { continue }
                    if let bundleID = info.bundleID {
                        if bundleID == ownBundleID { continue }
                        guard seenBundles.insert(bundleID).inserted else { continue }
                    }
                    result.append(info)
                } else if depth > 0 {
                    let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values?.isDirectory == true, values?.isSymbolicLink != true {
                        visit(entry, depth: depth - 1)
                    }
                }
            }
        }

        for source in sources {
            visit(URL(fileURLWithPath: expand(source), isDirectory: true), depth: 1)
        }
        AppleAppLocalizer.warm(apps: result, languageCode: LocalizationManager.activeLanguageCode)
        return result
    }

    static func makeInfo(_ url: URL, resolvedPath: String, addedDate: Date? = nil, modTime: TimeInterval = 0) -> AppInfo? {
        let standardized = url.standardizedFileURL
        let pathKey = standardized.path
        if modTime > 0 {
            infoCacheLock.lock()
            let cached = cachedScanEntries[pathKey]
            infoCacheLock.unlock()
            if let cached, cached.modTime == modTime, cached.info.resolvedPath == resolvedPath {
                return cached.info
            }
        }

        let plist = infoDictionary(for: standardized)
        var name = FileManager.default.displayName(atPath: pathKey)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        if name.isEmpty { name = standardized.deletingPathExtension().lastPathComponent }

        let resolvedDateAdded = addedDate
            ?? (try? standardized.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate

        let info = AppInfo(
            id: pathKey,
            url: standardized,
            resolvedPath: resolvedPath,
            name: name,
            bundleID: plist?["CFBundleIdentifier"] as? String,
            category: plist?["LSApplicationCategoryType"] as? String,
            dateAdded: resolvedDateAdded,
            lastUsed: nil,
            bundleModTime: modTime
        )
        if modTime > 0 {
            infoCacheLock.lock()
            cachedScanEntries[pathKey] = (modTime, info)
            infoCacheLock.unlock()
        }
        return info
    }

    /// Requête Spotlight paresseuse appelée uniquement lors d'un tri manuel par date d'ajout ou dernière utilisation.
    static func metadataDates(for appIDs: [String]) -> [String: (added: Date?, lastUsed: Date?)] {
        var result: [String: (Date?, Date?)] = [:]
        result.reserveCapacity(appIDs.count)
        for path in appIDs {
            let url = URL(fileURLWithPath: path)
            if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
                let added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
                let last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
                result[path] = (added, last)
            }
        }
        return result
    }

    /// Lit directement l'Info.plist (plus léger que `Bundle(url:)` qui met tout en cache).
    /// Gère aussi les apps iOS sur Apple Silicon (WrappedBundle).
    static func infoDictionary(for url: URL) -> [String: Any]? {
        for relative in ["Contents/Info.plist", "WrappedBundle/Info.plist", "Info.plist"] {
            let plistURL = url.appendingPathComponent(relative)
            if let data = try? Data(contentsOf: plistURL),
               let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                return object
            }
        }
        return nil
    }
}

// MARK: - Surveillance des dossiers (équivalent léger du FinderMonitor de LaunchOS)

@MainActor
final class FolderWatcher {
    private final class SourceBox {
        var sources: [DispatchSourceFileSystemObject] = []
        nonisolated deinit {
            for s in sources { s.cancel() }
        }
    }

    private let box = SourceBox()
    private var watchedPaths: [String] = []
    var onChange: (() -> Void)?

    func watch(_ paths: [String]) {
        guard paths != watchedPaths else { return }
        stop()
        watchedPaths = paths
        for path in paths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .link],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.onChange?() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            box.sources.append(source)
        }
    }

    func stop() {
        box.sources.forEach { $0.cancel() }
        box.sources.removeAll()
        watchedPaths.removeAll()
    }
}

// MARK: - Icônes (cache disque + mémoire + miniatures 64×64, pré-rendu en arrière-plan)

nonisolated private enum IconDiskCache {
    private static let cacheDir: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("LaucnhPad/IconsV2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let writeQueue = DispatchQueue(label: "me.LaucnhPad.iconDiskCache", qos: .utility)
    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
    private static let decodeOptions: CFDictionary = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary

    static func styleFolderName(style: IconAppearanceStyle, tintKey: String, isPro: Bool) -> String {
        let tintPart = style == .tinted ? tintKey : "none"
        return "\(style.rawValue)_\(tintPart)_p\(isPro ? 1 : 0)"
    }

    static func hexFilename(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        var chars = [UInt8](repeating: 0, count: 32)
        var i = 0
        for byte in digest.prefix(16) {
            chars[i] = hexDigits[Int(byte >> 4)]
            chars[i + 1] = hexDigits[Int(byte & 0x0F)]
            i += 2
        }
        return String(decoding: chars, as: UTF8.self) + ".png"
    }

    static func folderURL(style: IconAppearanceStyle, tintKey: String, isPro: Bool) -> URL? {
        cacheDir?.appendingPathComponent(styleFolderName(style: style, tintKey: tintKey, isPro: isPro), isDirectory: true)
    }

    static func fileURL(for path: String, style: IconAppearanceStyle, tintKey: String, isPro: Bool) -> URL? {
        folderURL(style: style, tintKey: tintKey, isPro: isPro)?
            .appendingPathComponent(hexFilename(for: path))
    }

    static func loadCGImage(for path: String, style: IconAppearanceStyle, tintKey: String, isPro: Bool) -> CGImage? {
        guard let url = fileURL(for: path, style: style, tintKey: tintKey, isPro: isPro),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, decodeOptions),
              cg.width >= IconRenderer.pixelSize else {
            return nil
        }
        return cg
    }

    static func hasCachedFile(for path: String, style: IconAppearanceStyle, tintKey: String, isPro: Bool) -> Bool {
        guard let url = fileURL(for: path, style: style, tintKey: tintKey, isPro: isPro) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func loadImage(for path: String, style: IconAppearanceStyle, tintKey: String, isPro: Bool) -> NSImage? {
        guard let cg = loadCGImage(for: path, style: style, tintKey: tintKey, isPro: isPro) else { return nil }
        return CustomAppIconRenderer.wrapCGImageAsRetinaNSImage(cg)
    }

    @inline(__always)
    static func writePNG(_ cg: CGImage, to url: URL) {
        let tmpURL = url.appendingPathExtension("tmp")
        guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        if CGImageDestinationFinalize(dest) {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: tmpURL)
            } else {
                try? fm.moveItem(at: tmpURL, to: url)
            }
        } else {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    static func saveInBackground(_ rendered: [String: CGImage], style: IconAppearanceStyle, tintKey: String, isPro: Bool) {
        guard !rendered.isEmpty, let folder = folderURL(style: style, tintKey: tintKey, isPro: isPro) else { return }
        let snapshot = rendered
        writeQueue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for (path, cg) in snapshot {
                autoreleasepool {
                    let url = folder.appendingPathComponent(hexFilename(for: path))
                    guard !fm.fileExists(atPath: url.path) else { return }
                    writePNG(cg, to: url)
                }
            }
        }
    }

    static func invalidate(paths: [String]) {
        guard !paths.isEmpty, let cacheDir else { return }
        let filenames = paths.map { hexFilename(for: $0) }
        writeQueue.async {
            let fm = FileManager.default
            guard let subdirs = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
            for subdir in subdirs {
                for name in filenames {
                    let file = subdir.appendingPathComponent(name)
                    if fm.fileExists(atPath: file.path) {
                        try? fm.removeItem(at: file)
                    }
                }
            }
        }
    }

    static func clearAll() {
        guard let cacheDir else { return }
        writeQueue.async {
            try? FileManager.default.removeItem(at: cacheDir)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()

    private static func makeImageCache(costLimit: Int) -> NSCache<NSString, NSImage> {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = costLimit
        return cache
    }

    private var imagesCache = IconCache.makeImageCache(costLimit: 96 * 1024 * 1024)
    private var staleStyleCache: NSCache<NSString, NSImage>?
    private let overrideImagesCache = IconCache.makeImageCache(costLimit: 24 * 1024 * 1024)
    private let miniImagesCache = IconCache.makeImageCache(costLimit: 12 * 1024 * 1024)
    private let fallbackImagesCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 80
        return cache
    }()
    private var pendingAsyncPaths: Set<String> = []
    private var flushTask: Task<Void, Never>?
    private var activeBatchTask: Task<Void, Never>?
    private var cachedStyleTuple: (raw: String, tinted: Bool, isPro: Bool, tintKey: String, style: IconAppearanceStyle, tintRGB: (r: Double, g: Double, b: Double))?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var defaultsObserver: NSObjectProtocol?
    var onAsyncBatchReady: (() -> Void)?

    init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.imagesCache.removeAllObjects()
            self.staleStyleCache = nil
            self.miniImagesCache.removeAllObjects()
            self.fallbackImagesCache.removeAllObjects()
        }
        source.resume()
        self.memoryPressureSource = source

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cachedStyleTuple = nil
            }
        }
    }

    private func resolvedAppearance() -> (style: IconAppearanceStyle, isPro: Bool, tintKey: String, tintRGB: (r: Double, g: Double, b: Double)) {
        if let c = cachedStyleTuple {
            return (c.style, c.isPro, c.tintKey, c.tintRGB)
        }
        let defaults = UserDefaults.standard
        let isPro = defaults.bool(forKey: PrefKey.isProUnlocked)
        let tinted = defaults.bool(forKey: PrefKey.tintedIcons)
        let raw = defaults.string(forKey: PrefKey.iconStyle) ?? "original"
        let tintKey = defaults.string(forKey: PrefKey.tintedIconColor) ?? "blue"

        let style: IconAppearanceStyle = {
            if tinted && isPro { return .tinted }
            let parsed = IconAppearanceStyle(rawValue: raw) ?? .original
            return (parsed.requiresPro && !isPro) ? .original : parsed
        }()

        let rgb: (Double, Double, Double) = {
            switch tintKey {
            case "graphite": return (0.78, 0.78, 0.78)
            case "purple": return (0.65, 0.42, 1.0)
            case "orange": return (1.0, 0.56, 0.14)
            case "mint": return (0.18, 0.85, 0.68)
            case "rose": return (1.0, 0.32, 0.56)
            case "gold": return (0.98, 0.78, 0.22)
            default: return (0.08, 0.54, 0.98)
            }
        }()

        cachedStyleTuple = (raw, tinted, isPro, tintKey, style, rgb)
        return (style, isPro, tintKey, rgb)
    }

    func invalidateStyleCache() {
        cachedStyleTuple = nil
    }

    /// Style courant (mis en cache pour éviter des lectures répétées de UserDefaults).
    var useOriginalColors: Bool { currentAppearanceStyle != .system }

    var currentAppearanceStyle: IconAppearanceStyle {
        resolvedAppearance().style
    }

    var activeTintKey: String {
        resolvedAppearance().tintKey
    }

    var activeTintRGB: (r: Double, g: Double, b: Double) {
        resolvedAppearance().tintRGB
    }

    var activeTintColor: Color {
        let rgb = activeTintRGB
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    @inline(__always)
    private static func bitmapCost(_ cgImage: CGImage) -> Int {
        max(1, cgImage.width * cgImage.height * 4)
    }

    func icon(for path: String) -> NSImage {
        let key = path as NSString

        if !path.hasPrefix("web:") && !path.hasPrefix("shortcut:"),
           CustomIconManager.shared.hasOverride(for: path) {
            if let overrideImg = overrideImagesCache.object(forKey: key) {
                return overrideImg
            }
            let appName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let resolved = resolvedAppearance()
            if let customImg = CustomAppIconRenderer.renderIcon(
                for: path,
                bundleID: nil,
                name: appName,
                style: resolved.style,
                tintColor: Color(red: resolved.tintRGB.r, green: resolved.tintRGB.g, blue: resolved.tintRGB.b),
                pixelSize: 256
            ) {
                overrideImagesCache.setObject(customImg, forKey: key, cost: 512 * 512 * 4)
                return customImg
            }
        }

        if let cached = imagesCache.object(forKey: key) {
            return cached
        }

        // Pendant une transition de thème, conserver l'ancien rendu stylisé le temps du chargement asynchrone
        // pour éviter tout flash blanc ou appel synchrone à NSWorkspace / disque sur le thread principal.
        if let stale = staleStyleCache?.object(forKey: key) {
            scheduleBackgroundRenderIfNeeded(path: path)
            return stale
        }

        if let fallback = fallbackImagesCache.object(forKey: key) {
            scheduleBackgroundRenderIfNeeded(path: path)
            return fallback
        }

        // Ne jamais bloquer @MainActor avec un décodage PNG ou un rendu pixel-shader 512×512 synchrone :
        // on retourne instantanément un aperçu léger puis le rendu HD (disque ou shader) arrive en arrière-plan.
        let fastFallback: NSImage
        if path.hasPrefix("web:") || path.hasPrefix("shortcut:") {
            fastFallback = CustomTileRenderer.icon(forID: path)
        } else {
            fastFallback = NSWorkspace.shared.icon(forFile: path)
            fastFallback.size = NSSize(width: 256, height: 256)
        }
        fallbackImagesCache.setObject(fastFallback, forKey: key)
        scheduleBackgroundRenderIfNeeded(path: path)
        return fastFallback
    }

    /// Miniature 64×64 Retina dédiée aux grilles 3×3 des dossiers et aperçus compacts (réduit de 16× la RAM GPU).
    func miniIcon(for path: String) -> NSImage {
        let key = path as NSString
        if let mini = miniImagesCache.object(forKey: key) {
            return mini
        }
        let full = icon(for: path)
        guard imagesCache.object(forKey: key) != nil || overrideImagesCache.object(forKey: key) != nil else {
            return full
        }
        let thumb = Self.makeMiniThumbnail(from: full, targetPx: 64)
        miniImagesCache.setObject(thumb, forKey: key, cost: 64 * 64 * 4)
        return thumb
    }

    /// Version synchrone haute résolution utilisée exclusivement par les diagnostics admin (`validateCatalogIcons`).
    func highResIconSync(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = imagesCache.object(forKey: key) ?? overrideImagesCache.object(forKey: key) {
            return cached
        }
        let resolved = resolvedAppearance()
        if let diskCG = IconDiskCache.loadCGImage(for: path, style: resolved.style, tintKey: resolved.tintKey, isPro: resolved.isPro) {
            let hd = CustomAppIconRenderer.wrapCGImageAsRetinaNSImage(diskCG)
            imagesCache.setObject(hd, forKey: key, cost: Self.bitmapCost(diskCG))
            fallbackImagesCache.removeObject(forKey: key)
            return hd
        }
        if let cg = IconRenderer.renderStyledHighResIcon(for: path, style: resolved.style, tintRGB: resolved.tintRGB, isPro: resolved.isPro) {
            let hd = CustomAppIconRenderer.wrapCGImageAsRetinaNSImage(cg)
            imagesCache.setObject(hd, forKey: key, cost: Self.bitmapCost(cg))
            fallbackImagesCache.removeObject(forKey: key)
            return hd
        }
        return icon(for: path)
    }

    private func scheduleBackgroundRenderIfNeeded(path: String) {
        guard pendingAsyncPaths.insert(path).inserted else { return }
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled else { return }
            let paths = Array(self.pendingAsyncPaths)
            self.pendingAsyncPaths.removeAll(keepingCapacity: true)
            self.flushTask = nil
            guard !paths.isEmpty else { return }
            let resolved = self.resolvedAppearance()
            self.activeBatchTask?.cancel()
            self.activeBatchTask = Task { [weak self] in
                let batch = await IconRenderer.renderAsyncWithDiskCache(
                    paths,
                    style: resolved.style,
                    tintKey: resolved.tintKey,
                    tintRGB: resolved.tintRGB,
                    isPro: resolved.isPro,
                    priority: .userInitiated
                )
                guard let self, !Task.isCancelled else { return }
                self.store(
                    batch.images,
                    newlyRendered: batch.newlyRendered,
                    forStyle: resolved.style,
                    tintKey: resolved.tintKey,
                    isPro: resolved.isPro
                )
                if !batch.images.isEmpty {
                    self.onAsyncBatchReady?()
                }
            }
        }
    }

    private static func makeMiniThumbnail(from image: NSImage, targetPx: Int) -> NSImage {
        var proposed = NSRect(x: 0, y: 0, width: targetPx, height: targetPx)
        guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: targetPx,
                height: targetPx,
                bitsPerComponent: 8,
                bytesPerRow: targetPx * 4,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetPx, height: targetPx))
        guard let outCG = ctx.makeImage() else { return image }
        let pt = targetPx / 2
        return NSImage(cgImage: outCG, size: NSSize(width: pt, height: pt))
    }

    func contains(_ path: String) -> Bool {
        let key = path as NSString
        return imagesCache.object(forKey: key) != nil || overrideImagesCache.object(forKey: key) != nil
    }

    func store(
        _ rendered: [String: CGImage],
        newlyRendered: [String: CGImage]? = nil,
        miniThumbnails: [String: CGImage] = [:],
        forStyle expectedStyle: IconAppearanceStyle? = nil,
        tintKey expectedTintKey: String? = nil,
        isPro expectedIsPro: Bool? = nil
    ) {
        let resolved = resolvedAppearance()
        if let expectedStyle, expectedStyle != resolved.style { return }
        if let expectedIsPro, expectedIsPro != resolved.isPro { return }
        if resolved.style == .tinted, let expectedTintKey, expectedTintKey != resolved.tintKey { return }
        for (path, cgImage) in rendered {
            let key = path as NSString
            if imagesCache.object(forKey: key) != nil { continue }
            if CustomIconManager.shared.hasOverride(for: path) { continue }
            imagesCache.setObject(
                CustomAppIconRenderer.wrapCGImageAsRetinaNSImage(cgImage),
                forKey: key,
                cost: Self.bitmapCost(cgImage)
            )
            fallbackImagesCache.removeObject(forKey: key)
            miniImagesCache.removeObject(forKey: key)
        }
        for (path, miniCG) in miniThumbnails {
            let key = path as NSString
            if CustomIconManager.shared.hasOverride(for: path) { continue }
            let pt = miniCG.width / 2
            miniImagesCache.setObject(
                NSImage(cgImage: miniCG, size: NSSize(width: pt, height: pt)),
                forKey: key,
                cost: Self.bitmapCost(miniCG)
            )
        }
        let toPersist = newlyRendered ?? rendered
        if !toPersist.isEmpty {
            IconDiskCache.saveInBackground(toPersist, style: resolved.style, tintKey: resolved.tintKey, isPro: resolved.isPro)
        }
    }

    func finishStyleTransition() {
        staleStyleCache = nil
    }

    func trimTransientCaches() {
        staleStyleCache = nil
        fallbackImagesCache.removeAllObjects()
    }

    func invalidate(_ paths: [String]) {
        for path in paths {
            let key = path as NSString
            imagesCache.removeObject(forKey: key)
            staleStyleCache?.removeObject(forKey: key)
            overrideImagesCache.removeObject(forKey: key)
            miniImagesCache.removeObject(forKey: key)
            fallbackImagesCache.removeObject(forKey: key)
        }
        IconDiskCache.invalidate(paths: paths)
    }

    /// Vide uniquement les rendus de thème tout en conservant les icônes personnalisées de l'utilisateur.
    func removeStyleImages() {
        flushTask?.cancel()
        flushTask = nil
        activeBatchTask?.cancel()
        activeBatchTask = nil
        cachedStyleTuple = nil
        staleStyleCache = imagesCache
        imagesCache = Self.makeImageCache(costLimit: 96 * 1024 * 1024)
        miniImagesCache.removeAllObjects()
        fallbackImagesCache.removeAllObjects()
        pendingAsyncPaths.removeAll(keepingCapacity: true)
    }

    func removeAll() {
        flushTask?.cancel()
        flushTask = nil
        activeBatchTask?.cancel()
        activeBatchTask = nil
        cachedStyleTuple = nil
        staleStyleCache = nil
        imagesCache.removeAllObjects()
        overrideImagesCache.removeAllObjects()
        miniImagesCache.removeAllObjects()
        fallbackImagesCache.removeAllObjects()
        pendingAsyncPaths.removeAll()
    }
}

nonisolated enum IconRenderer {
    /// Résolution Retina haute densité 512×512 pixels physiques (pour affichage net jusqu'à 256pt @2x)
    static let pixelSize = 512
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    // Géométries et LUTs pré-calculées pour éviter toute réallocation / powf() dans la boucle pixel par pixel
    private static let standardBodyRect512: CGRect = {
        let inset = CGFloat(pixelSize) * 0.091
        let body = CGFloat(pixelSize) - inset * 2
        return CGRect(x: inset, y: inset, width: body, height: body)
    }()
    private static let cachedBodySquirclePath512: CGPath = createAppleSquirclePath(in: standardBodyRect512, cornerRatio: 0.225)
    private static let cachedInnerTrimPath512: CGPath = {
        let rimInset = CGFloat(pixelSize) * 0.0105
        return createAppleSquirclePath(in: standardBodyRect512.insetBy(dx: rimInset, dy: rimInset), cornerRatio: 0.225)
    }()
    private static let cachedULUT512: [Float] = makeULUT(size: pixelSize)
    private static let pow074LUT: [Float] = (0..<4096).map { powf(Float($0) / 4095.0, 0.74) }
    private static let pow088LUT: [Float] = (0..<4096).map { powf(Float($0) / 4095.0, 0.88) }

    private static func makeULUT(size: Int) -> [Float] {
        let rimSampleInset = Int(Float(size) * 0.114)
        let rimMax = size - 1 - rimSampleInset
        let invSpan: Float = 1.0 / Float(max(1, rimMax - rimSampleInset))
        var lut = [Float](repeating: 0, count: size)
        for i in 0..<size {
            lut[i] = Float(max(rimSampleInset, min(rimMax, i)) - rimSampleInset) * invSpan
        }
        return lut
    }

    /// Icône source haute définition : extrait en priorité l'asset 1024×1024 / 512×512 en couleur depuis Assets.car ou .icns
    static func sourceIcon(for path: String, original: Bool) -> NSImage {
        if path.hasPrefix("web:") || path.hasPrefix("shortcut:") {
            return CustomTileRenderer.icon(forID: path)
        }
        if original, let image = bundleIcon(for: path) {
            return image
        }
        let ws = NSWorkspace.shared.icon(forFile: path)
        ws.size = NSSize(width: pixelSize, height: pixelSize)
        return ws
    }

    /// Extrait la meilleure représentation haute résolution (jusqu'à 1024×1024) depuis Assets.car ou les fichiers .icns du bundle
    static func bundleIcon(for path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let info = AppScanner.infoDictionary(for: url)

        let iconName = (info?["CFBundleIconName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let iconFile = (info?["CFBundleIconFile"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        var candidates: [String] = []
        if let iconName { candidates.append(iconName) }
        if let iconFile {
            if !candidates.contains(iconFile) { candidates.append(iconFile) }
            let stripped = (iconFile as NSString).deletingPathExtension
            if !stripped.isEmpty && !candidates.contains(stripped) {
                candidates.append(stripped)
            }
        }
        if !candidates.contains("AppIcon") {
            candidates.append("AppIcon")
        }

        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        let hasAssetsCar = FileManager.default.fileExists(atPath: resources.appendingPathComponent("Assets.car").path)

        // 1. Lecture depuis Assets.car uniquement si présent (évite la rétention permanente de Bundle(url:) sinon)
        if hasAssetsCar, let bundle = Bundle(url: url) {
            for candidate in candidates {
                if let bImg = bundle.image(forResource: candidate), bImg.isValid, !bImg.representations.isEmpty {
                    let copy = (bImg.copy() as? NSImage) ?? bImg
                    copy.size = NSSize(width: pixelSize, height: pixelSize)
                    return copy
                }
            }
        }

        // 2. Lecture directe des fichiers .icns nommés dans Contents/Resources/
        for candidate in candidates {
            let fileName = (candidate as NSString).pathExtension.isEmpty ? candidate + ".icns" : candidate
            let iconURL = resources.appendingPathComponent(fileName)
            let size = (try? FileManager.default.attributesOfItem(atPath: iconURL.path)[.size] as? Int) ?? 0
            if size > 4_000, let image = NSImage(contentsOf: iconURL), image.isValid, !image.representations.isEmpty {
                image.size = NSSize(width: pixelSize, height: pixelSize)
                return image
            }
        }

        // 3. Recherche du plus gros fichier .icns (tri par taille fichier avant décodage)
        if let files = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: [.fileSizeKey]) {
            let sortedIcns = files
                .filter { $0.pathExtension.lowercased() == "icns" }
                .compactMap { fileURL -> (url: URL, size: Int)? in
                    let fSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return fSize > 4_000 ? (fileURL, fSize) : nil
                }
                .sorted { $0.size > $1.size }
            for entry in sortedIcns.prefix(2) {
                if let img = NSImage(contentsOf: entry.url) {
                    let maxP = img.representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
                    if maxP >= 128 * 128 {
                        img.size = NSSize(width: pixelSize, height: pixelSize)
                        return img
                    }
                }
            }
        }
        return nil
    }

    /// Rastérise un NSImage à sa résolution maximale (512×512 ou 1024×1024 réduite proprement en 512×512)
    static func rasterizeNSImageHighRes(_ icon: NSImage, targetSize: Int = pixelSize) -> CGImage? {
        // Mise à l'échelle haute qualité si l'icône n'est pas déjà au bon format
        let copy = (icon.representations.count == 1 && icon.size == NSSize(width: targetSize, height: targetSize))
            ? icon
            : (icon.copy() as? NSImage ?? icon)
        if copy.size != NSSize(width: targetSize, height: targetSize) {
            copy.size = NSSize(width: targetSize, height: targetSize)
        }

        var proposedRect = NSRect(x: 0, y: 0, width: targetSize, height: targetSize)
        if let directCG = copy.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        ), directCG.width >= 256 {
            if directCG.width == targetSize && directCG.height == targetSize {
                return directCG
            }
            // Redimensionnement bicubique haute précision vers 512×512
            guard let cs = sRGBColorSpace,
                  let ctx = CGContext(
                      data: nil,
                      width: targetSize,
                      height: targetSize,
                      bitsPerComponent: 8,
                      bytesPerRow: targetSize * 4,
                      space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return directCG }
            ctx.interpolationQuality = .high
            ctx.draw(directCG, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
            return ctx.makeImage() ?? directCG
        }

        // Fallback de dessin direct dans un contexte 512×512
        guard let cs = sRGBColorSpace,
              let ctx = CGContext(
                  data: nil,
                  width: targetSize,
                  height: targetSize,
                  bitsPerComponent: 8,
                  bytesPerRow: targetSize * 4,
                  space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        copy.draw(
            in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Extrait, normalise les proportions squircle (sans effet boîte-dans-boîte) et applique le style choisi en 512×512
    static func renderStyledHighResIcon(
        for path: String,
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double),
        isPro: Bool = UserDefaults.standard.bool(forKey: PrefKey.isProUnlocked)
    ) -> CGImage? {
        let preferOriginal = (style != .system)
        let primarySource = sourceIcon(for: path, original: preferOriginal)
        if let rawCG = rasterizeNSImageHighRes(primarySource, targetSize: pixelSize),
           let styled = normalizeAndStyleCGImage(
               rawCG,
               style: style,
               tintRGB: tintRGB,
               forceSquircleClip: false,
               isPro: isPro,
               rejectBlank: true
           ) {
            return styled
        }

        let wsFallback = NSWorkspace.shared.icon(forFile: path)
        wsFallback.size = NSSize(width: pixelSize, height: pixelSize)
        guard let fallbackCG = rasterizeNSImageHighRes(wsFallback, targetSize: pixelSize) else { return nil }
        return normalizeAndStyleCGImage(
            fallbackCG,
            style: style,
            tintRGB: tintRGB,
            forceSquircleClip: false,
            isPro: isPro,
            rejectBlank: false
        )
    }

    /// Construit le tracé exact d'un squircle continu Apple (courbure G2 fluide sans cassure d'arc circulaire)
    private static func createAppleSquirclePath(in rect: CGRect, cornerRatio: CGFloat = 0.225) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width
        let h = rect.height
        let minDim = min(w, h)
        let r = minDim * cornerRatio
        // Facteurs exacts dérivés du RoundedRectangle(.continuous) d'Apple / SwiftUI
        let rawC = r * 1.52866494
        let c = min(minDim * 0.5, rawC)
        let s = rawC > 0 ? (c / rawC) : 1.0
        let k1 = r * 1.0884900 * s
        let k2 = r * 0.8684070 * s
        let k3 = r * 0.6314940 * s
        let k4 = r * 0.0749114 * s
        let k5 = r * 0.3728240 * s
        let k6 = r * 0.1690600 * s

        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        path.move(to: CGPoint(x: maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - c))
        // Coin haut-droit (en coordonnées CoreGraphics Y monte)
        path.addCurve(to: CGPoint(x: maxX - k4, y: maxY - k3),
                      control1: CGPoint(x: maxX, y: maxY - k1),
                      control2: CGPoint(x: maxX, y: maxY - k2))
        path.addCurve(to: CGPoint(x: maxX - k3, y: maxY - k4),
                      control1: CGPoint(x: maxX - k6, y: maxY - k5),
                      control2: CGPoint(x: maxX - k5, y: maxY - k6))
        path.addCurve(to: CGPoint(x: maxX - c, y: maxY),
                      control1: CGPoint(x: maxX - k2, y: maxY),
                      control2: CGPoint(x: maxX - k1, y: maxY))

        path.addLine(to: CGPoint(x: minX + c, y: maxY))
        // Coin haut-gauche
        path.addCurve(to: CGPoint(x: minX + k3, y: maxY - k4),
                      control1: CGPoint(x: minX + k1, y: maxY),
                      control2: CGPoint(x: minX + k2, y: maxY))
        path.addCurve(to: CGPoint(x: minX + k4, y: maxY - k3),
                      control1: CGPoint(x: minX + k5, y: maxY - k6),
                      control2: CGPoint(x: minX + k6, y: maxY - k5))
        path.addCurve(to: CGPoint(x: minX, y: maxY - c),
                      control1: CGPoint(x: minX, y: maxY - k2),
                      control2: CGPoint(x: minX, y: maxY - k1))

        path.addLine(to: CGPoint(x: minX, y: minY + c))
        // Coin bas-gauche
        path.addCurve(to: CGPoint(x: minX + k4, y: minY + k3),
                      control1: CGPoint(x: minX, y: minY + k1),
                      control2: CGPoint(x: minX, y: minY + k2))
        path.addCurve(to: CGPoint(x: minX + k3, y: minY + k4),
                      control1: CGPoint(x: minX + k6, y: minY + k5),
                      control2: CGPoint(x: minX + k5, y: minY + k6))
        path.addCurve(to: CGPoint(x: minX + c, y: minY),
                      control1: CGPoint(x: minX + k2, y: minY),
                      control2: CGPoint(x: minX + k1, y: minY))

        path.addLine(to: CGPoint(x: maxX - c, y: minY))
        // Coin bas-droit
        path.addCurve(to: CGPoint(x: maxX - k3, y: minY + k4),
                      control1: CGPoint(x: maxX - k1, y: minY),
                      control2: CGPoint(x: maxX - k2, y: minY))
        path.addCurve(to: CGPoint(x: maxX - k4, y: minY + k3),
                      control1: CGPoint(x: maxX - k5, y: minY + k6),
                      control2: CGPoint(x: maxX - k6, y: minY + k5))
        path.addCurve(to: CGPoint(x: maxX, y: minY + c),
                      control1: CGPoint(x: maxX, y: minY + k2),
                      control2: CGPoint(x: maxX, y: minY + k1))

        path.closeSubpath()
        return path
    }

    /// Normalise les marges transparentes de l'icône et applique le shader de style directement aux pixels 512×512
    static func normalizeAndStyleCGImage(
        _ sourceCG: CGImage,
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double),
        forceSquircleClip: Bool,
        isPro: Bool = UserDefaults.standard.bool(forKey: PrefKey.isProUnlocked),
        rejectBlank: Bool = false
    ) -> CGImage? {
        let size = pixelSize
        guard let cs = sRGBColorSpace else { return sourceCG }

        let total = size * size
        let byteCount = total * 4
        var pixels = [UInt8](repeating: 0, count: byteCount)

        // 1. Lecture des pixels sources en 512×512 pour détecter la boîte englobante visible (alphaBounds)
        let drawnFirst = pixels.withUnsafeMutableBytes { rawBuf -> Bool in
            guard let base = rawBuf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: size,
                      height: size,
                      bitsPerComponent: 8,
                      bytesPerRow: size * 4,
                      space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(sourceCG, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawnFirst else { return sourceCG }

        var minX = size, minY = size, maxX = -1, maxY = -1
        pixels.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            let rowStride = size * 4
            for y in 0..<size {
                let rowOff = y * rowStride
                var firstX = -1
                var x = 0
                while x < size {
                    if base[rowOff + x * 4 + 3] > 24 {
                        firstX = x
                        break
                    }
                    x += 1
                }
                guard firstX >= 0 else { continue }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                if firstX < minX { minX = firstX }
                var rx = size - 1
                let stopX = max(firstX, maxX)
                while rx > stopX {
                    if base[rowOff + rx * 4 + 3] > 24 {
                        maxX = rx
                        break
                    }
                    rx -= 1
                }
                if firstX > maxX { maxX = firstX }
            }
        }
        if rejectBlank && maxX < minX {
            return nil
        }

        // Cadre squircle standard macOS : 81.6% de la toile 512×512 (soit 418×418 px centré, marge = 47 px)
        let standardBody = standardBodyRect512.width
        let bodySquirclePath = cachedBodySquirclePath512
        let fgInnerTrimPath = cachedInnerTrimPath512

        let visibleW = maxX >= minX ? CGFloat(maxX - minX + 1) : standardBody
        let visibleH = maxY >= minY ? CGFloat(maxY - minY + 1) : standardBody
        let maxVisibleDim = max(visibleW, visibleH)

        // Si l'icône déborde des marges standards (> 87% du canevas, ex. Wallper ou image plein cadre)
        // ou si elle est trop petite (< 72%), on la recadre proportionnellement dans le squircle standard
        let needsRescale = forceSquircleClip || maxVisibleDim > CGFloat(size) * 0.87 || maxVisibleDim < CGFloat(size) * 0.72
        let needsCornerClip = forceSquircleClip || maxVisibleDim > CGFloat(size) * 0.87

        // Évite toute réallocation de tampon et tout second tracé si l'icône est déjà aux dimensions standards
        if needsRescale || needsCornerClip {
            let redrawn = pixels.withUnsafeMutableBytes { rawBuf -> Bool in
                guard let base = rawBuf.baseAddress else { return false }
                memset(base, 0, byteCount)
                guard let ctx = CGContext(
                    data: base,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: size * 4,
                    space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.interpolationQuality = .high
                if needsCornerClip {
                    ctx.addPath(bodySquirclePath)
                    ctx.clip()
                }
                if needsRescale && maxVisibleDim > 0 {
                    let scale = standardBody / maxVisibleDim
                    let centerX = CGFloat(minX + maxX) * 0.5
                    let centerY = CGFloat(size) - CGFloat(minY + maxY) * 0.5
                    let drawW = CGFloat(size) * scale
                    let drawH = CGFloat(size) * scale
                    let drawX = CGFloat(size) * 0.5 - centerX * scale
                    let drawY = CGFloat(size) * 0.5 - centerY * scale
                    ctx.draw(sourceCG, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
                } else {
                    ctx.draw(sourceCG, in: CGRect(x: 0, y: 0, width: size, height: size))
                }
                return true
            }
            if !redrawn { return sourceCG }
        }

        // 2. Application du filtre de style pixel par pixel en 512×512 (détourage haute précision + décontamination des bords)
        var strippedSquircleCard = false
        if style != .original && style != .system && style != .classicApple {
            strippedSquircleCard = applyPixelStyleShader(&pixels, size: size, style: style, tintRGB: tintRGB, isPro: isPro)
        }

        let styledCG: CGImage? = pixels.withUnsafeMutableBytes { rawBuf in
            guard let base = rawBuf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: size,
                      height: size,
                      bitsPerComponent: 8,
                      bytesPerRow: size * 4,
                      space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            return ctx.makeImage()
        }
        guard let styledCG else { return sourceCG }

        // 3. Composition finale :
        // En mode Cristal Pur (Version 1), on conserve uniquement l'avant-plan détouré et net sur fond alpha
        // afin que SwiftUI applique la véritable réfraction optique macOS 26 (.glassEffect(.clear)) + le biseau spéculaire.
        guard let finalCtx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return styledCG }
        finalCtx.interpolationQuality = .high

        let fSize = CGFloat(size)
        let usesLiveCrystal = style.usesCrystalGlassBackdrop(isPro: isPro)

        if usesLiveCrystal {
            finalCtx.saveGState()
            if strippedSquircleCard {
                finalCtx.addPath(fgInnerTrimPath)
                finalCtx.clip()
            } else {
                finalCtx.addPath(bodySquirclePath)
                finalCtx.clip()
            }
            finalCtx.draw(styledCG, in: CGRect(x: 0, y: 0, width: fSize, height: fSize))
            finalCtx.restoreGState()
        } else {
            finalCtx.saveGState()
            finalCtx.setShadow(
                offset: CGSize(width: 0, height: -fSize * 0.012),
                blur: fSize * 0.034,
                color: CGColor(gray: 0, alpha: style == .light ? 0.22 : 0.32)
            )
            finalCtx.draw(styledCG, in: CGRect(x: 0, y: 0, width: fSize, height: fSize))
            finalCtx.restoreGState()
        }

        return finalCtx.makeImage() ?? styledCG
    }

    private struct SmoothMatteAnalysis {
        let matte: [Float]
        let bilinearCorners: (tl: (r: Float, g: Float, b: Float), tr: (r: Float, g: Float, b: Float), bl: (r: Float, g: Float, b: Float), br: (r: Float, g: Float, b: Float))
        let uLUT: [Float]
        let avgBGLuminance: Float
        let isSquircleCard: Bool
    }

    @inline(__always)
    private static func sampleNormalizedRGB(px: [UInt8], size: Int, x: Int, y: Int, inv255: Float) -> (r: Float, g: Float, b: Float)? {
        guard x >= 0, x < size, y >= 0, y < size else { return nil }
        let off = (y * size + x) * 4
        let aByte = px[off + 3]
        guard aByte > 183 else { return nil } // a > 0.72 * 255
        if aByte == 255 {
            return (Float(px[off]) * inv255, Float(px[off + 1]) * inv255, Float(px[off + 2]) * inv255)
        }
        let invA = 1.0 / (255.0 * Float(aByte) * inv255)
        return (
            min(1.0, Float(px[off]) * invA),
            min(1.0, Float(px[off + 1]) * invA),
            min(1.0, Float(px[off + 2]) * invA)
        )
    }

    private static func medianClusterSample(
        px: [UInt8],
        size: Int,
        cx: Int,
        cy: Int,
        span: Int,
        inv255: Float,
        rs: inout [Float],
        gs: inout [Float],
        bs: inout [Float]
    ) -> (r: Float, g: Float, b: Float)? {
        rs.removeAll(keepingCapacity: true)
        gs.removeAll(keepingCapacity: true)
        bs.removeAll(keepingCapacity: true)
        let step = max(2, span / 2)
        for dy in stride(from: -span, through: span, by: step) {
            for dx in stride(from: -span, through: span, by: step) {
                if let c = sampleNormalizedRGB(px: px, size: size, x: cx + dx, y: cy + dy, inv255: inv255) {
                    rs.append(c.r)
                    gs.append(c.g)
                    bs.append(c.b)
                }
            }
        }
        guard rs.count >= 3 else { return nil }
        rs.sort()
        gs.sort()
        bs.sort()
        let mid = rs.count / 2
        return (rs[mid], gs[mid], bs[mid])
    }

    @inline(__always)
    private static func perceptualColorDist(_ a: (r: Float, g: Float, b: Float), _ b: (r: Float, g: Float, b: Float)) -> Float {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        let dl = 0.299 * dr + 0.587 * dg + 0.114 * db
        let c2 = (dr - dl) * (dr - dl) + (dg - dl) * (dg - dl) + (db - dl) * (db - dl)
        return sqrtf(dl * dl * 0.90 + c2 * 1.45)
    }

    private static func runMatteFloodFill(
        size: Int,
        px: UnsafeBufferPointer<UInt8>,
        rgb: UnsafeBufferPointer<Float>,
        bgDistSq: UnsafeBufferPointer<Float>,
        rimSampleInset: Int,
        rimMax: Int,
        maxCornerSpread: Float,
        isBrightWhiteBG: Bool,
        isPaleGrayBG: Bool,
        avgBGLum: Float,
        directDist: Float,
        gradDistMax: Float,
        stepSqMax: Float
    ) -> [UInt8] {
        let total = size * size
        var isBackground = [UInt8](repeating: 0, count: total)
        var queue = [Int32](repeating: 0, count: total)
        let directDistSq = directDist * directDist
        let gradDistMaxSq = gradDistMax * gradDistMax
        let bevelDistSq: Float = 0.34 * 0.34

        let pxBase = px.baseAddress!
        let rgbBase = rgb.baseAddress!
        let distBase = bgDistSq.baseAddress!

        isBackground.withUnsafeMutableBufferPointer { bgBuf in
            queue.withUnsafeMutableBufferPointer { qBuf in
                let bgBase = bgBuf.baseAddress!
                let qBase = qBuf.baseAddress!
                var tail = 0

                @inline(__always)
                func seed(_ idx: Int) {
                    if bgBase[idx] == 0 && (pxBase[idx * 4 + 3] <= 38 || distBase[idx] < directDistSq) {
                        bgBase[idx] = 1
                        qBase[tail] = Int32(idx)
                        tail += 1
                    }
                }

                let outerSeedInset = Int(Float(size) * 0.104)
                let outerSeedMax = size - 1 - outerSeedInset
                let lastRowBase = (size - 1) * size
                for i in 0..<size {
                    seed(i)
                    seed(lastRowBase + i)
                    seed(i * size)
                    seed(i * size + (size - 1))
                    if i >= rimSampleInset && i <= rimMax {
                        seed(rimSampleInset * size + i)
                        seed(rimMax * size + i)
                        seed(i * size + rimSampleInset)
                        seed(i * size + rimMax)
                    }
                    if i >= outerSeedInset && i <= outerSeedMax {
                        seed(outerSeedInset * size + i)
                        seed(outerSeedMax * size + i)
                        seed(i * size + outerSeedInset)
                        seed(i * size + outerSeedMax)
                    }
                }

                var head = 0
                let maxIdx = size - 1
                let isPow2Size = (size & (size - 1)) == 0
                let sizeMask = size - 1
                let sizeShift = isPow2Size ? size.trailingZeroBitCount : 0
                let edgeBevelBandLow = Int(Float(size) * 0.088)
                let edgeBevelBandHigh = Int(Float(size) * 0.106)
                let edgeBevelHiLow = maxIdx - edgeBevelBandHigh
                let edgeBevelHiMax = maxIdx - edgeBevelBandLow

                @inline(__always)
                func tryNeighbor(
                    _ nIdx: Int,
                    nx: Int,
                    ny: Int,
                    curOnOuterBevelSeed: Bool,
                    canGradExpand: Bool,
                    cr: Float,
                    cg: Float,
                    cb: Float
                ) {
                    guard bgBase[nIdx] == 0 else { return }
                    let naByte = pxBase[nIdx * 4 + 3]
                    let ndSq = distBase[nIdx]
                    if naByte <= 20 || ndSq < directDistSq {
                        bgBase[nIdx] = 1
                        qBase[tail] = Int32(nIdx)
                        tail += 1
                    } else if curOnOuterBevelSeed && ndSq < bevelDistSq
                        && ((nx <= edgeBevelBandHigh && nx >= edgeBevelBandLow)
                            || (nx >= edgeBevelHiLow && nx <= edgeBevelHiMax)
                            || (ny <= edgeBevelBandHigh && ny >= edgeBevelBandLow)
                            || (ny >= edgeBevelHiLow && ny <= edgeBevelHiMax)) {
                        bgBase[nIdx] = 1
                        qBase[tail] = Int32(nIdx)
                        tail += 1
                    } else if canGradExpand && ndSq < gradDistMaxSq {
                        let o = nIdx * 3
                        let dr = rgbBase[o] - cr
                        let dg = rgbBase[o + 1] - cg
                        let db = rgbBase[o + 2] - cb
                        if (dr * dr + dg * dg + db * db) < stepSqMax {
                            bgBase[nIdx] = 1
                            qBase[tail] = Int32(nIdx)
                            tail += 1
                        }
                    }
                }

                while head < tail {
                    let cur = Int(qBase[head])
                    head += 1
                    let cx = isPow2Size ? (cur & sizeMask) : (cur % size)
                    let cy = isPow2Size ? (cur >> sizeShift) : (cur / size)
                    let curAlphaByte = pxBase[cur * 4 + 3]
                    let curRgbOff = cur * 3
                    let cr = rgbBase[curRgbOff], cg = rgbBase[curRgbOff + 1], cb = rgbBase[curRgbOff + 2]

                    let curOnOuterBevelSeed = curAlphaByte <= 127
                    let canGradExpand = curAlphaByte >= 166

                    if cx > 0 {
                        tryNeighbor(cur - 1, nx: cx - 1, ny: cy, curOnOuterBevelSeed: curOnOuterBevelSeed, canGradExpand: canGradExpand, cr: cr, cg: cg, cb: cb)
                    }
                    if cx < maxIdx {
                        tryNeighbor(cur + 1, nx: cx + 1, ny: cy, curOnOuterBevelSeed: curOnOuterBevelSeed, canGradExpand: canGradExpand, cr: cr, cg: cg, cb: cb)
                    }
                    if cy > 0 {
                        tryNeighbor(cur - size, nx: cx, ny: cy - 1, curOnOuterBevelSeed: curOnOuterBevelSeed, canGradExpand: canGradExpand, cr: cr, cg: cg, cb: cb)
                    }
                    if cy < maxIdx {
                        tryNeighbor(cur + size, nx: cx, ny: cy + 1, curOnOuterBevelSeed: curOnOuterBevelSeed, canGradExpand: canGradExpand, cr: cr, cg: cg, cb: cb)
                    }
                }

                // Passe conservatrice pour les poches de fond fermées (engrenage Réglages, boucles B/A, cellules de grille Moniteur d'activité)
                if maxCornerSpread < 0.25 {
                    let interiorLo = rimSampleInset - 6
                    let interiorHi = rimMax + 6
                    let holeSeedDist: Float = (!isBrightWhiteBG && !isPaleGrayBG && avgBGLum < 0.32) ? 0.140 : 0.068
                    let holeExpandDist: Float = (!isBrightWhiteBG && !isPaleGrayBG && avgBGLum < 0.32) ? 0.175 : 0.105
                    let holeSeedDistSq = holeSeedDist * holeSeedDist
                    let holeExpandDistSq = holeExpandDist * holeExpandDist
                    let flatSqMax: Float = 0.016 * 0.016
                    var hTail = 0
                    for y in stride(from: interiorLo, through: interiorHi, by: 2) {
                        let row = y * size
                        for x in stride(from: interiorLo, through: interiorHi, by: 2) {
                            let idx = row + x
                            guard bgBase[idx] == 0, pxBase[idx * 4 + 3] >= 217, distBase[idx] < holeSeedDistSq else { continue }
                            let o = idx * 3
                            let r = rgbBase[o], g = rgbBase[o + 1], b = rgbBase[o + 2]
                            let ro = (idx + 1) * 3, bo = (idx + size) * 3
                            let d1 = (rgbBase[ro] - r) * (rgbBase[ro] - r) + (rgbBase[ro + 1] - g) * (rgbBase[ro + 1] - g) + (rgbBase[ro + 2] - b) * (rgbBase[ro + 2] - b)
                            let d2 = (rgbBase[bo] - r) * (rgbBase[bo] - r) + (rgbBase[bo + 1] - g) * (rgbBase[bo + 1] - g) + (rgbBase[bo + 2] - b) * (rgbBase[bo + 2] - b)
                            if d1 < flatSqMax && d2 < flatSqMax {
                                bgBase[idx] = 1
                                qBase[hTail] = Int32(idx)
                                hTail += 1
                            }
                        }
                    }
                    var hHead = 0
                    let holeStepSq: Float = 0.020 * 0.020
                    @inline(__always)
                    func tryHoleNeighbor(_ nIdx: Int, cr: Float, cg: Float, cb: Float) {
                        if bgBase[nIdx] == 0 && pxBase[nIdx * 4 + 3] >= 192 && distBase[nIdx] < holeExpandDistSq {
                            let o = nIdx * 3
                            let dr = rgbBase[o] - cr
                            let dg = rgbBase[o + 1] - cg
                            let db = rgbBase[o + 2] - cb
                            if (dr * dr + dg * dg + db * db) < holeStepSq {
                                bgBase[nIdx] = 1
                                qBase[hTail] = Int32(nIdx)
                                hTail += 1
                            }
                        }
                    }
                    while hHead < hTail {
                        let cur = Int(qBase[hHead])
                        hHead += 1
                        let cx = isPow2Size ? (cur & sizeMask) : (cur % size)
                        let cy = isPow2Size ? (cur >> sizeShift) : (cur / size)
                        let curOff = cur * 3
                        let cr = rgbBase[curOff], cg = rgbBase[curOff + 1], cb = rgbBase[curOff + 2]
                        if cx > interiorLo { tryHoleNeighbor(cur - 1, cr: cr, cg: cg, cb: cb) }
                        if cx < interiorHi { tryHoleNeighbor(cur + 1, cr: cr, cg: cg, cb: cb) }
                        if cy > interiorLo { tryHoleNeighbor(cur - size, cr: cr, cg: cg, cb: cb) }
                        if cy < interiorHi { tryHoleNeighbor(cur + size, cr: cr, cg: cg, cb: cb) }
                    }
                }
            }
        }
        return isBackground
    }

    private static func centerForegroundRatio(size: Int, bgMask: [UInt8], px: UnsafeBufferPointer<UInt8>) -> Float {
        let lo = Int(Float(size) * 0.16)
        let hi = Int(Float(size) * 0.84)
        var totalCenter = 0
        var fgCenter = 0
        let pxBase = px.baseAddress!
        bgMask.withUnsafeBufferPointer { bgBuf in
            let bgBase = bgBuf.baseAddress!
            for y in stride(from: lo, to: hi, by: 2) {
                let row = y * size
                for x in stride(from: lo, to: hi, by: 2) {
                    let idx = row + x
                    totalCenter += 1
                    if bgBase[idx] == 0 && pxBase[idx * 4 + 3] >= 103 {
                        fgCenter += 1
                    }
                }
            }
        }
        return totalCenter > 0 ? Float(fgCenter) / Float(totalCenter) : 1.0
    }

    /// Analyse et détoure automatiquement le fond des icônes pour les modes Transparent / Liquid Glass.
    /// Combine détection de forme libre vs carte squircle, modélisation multi-ancres avec rejet d'anomalies,
    /// flood-fill double critère (teinte/luminance perceptuelle + continuité de dégradé), nettoyage des îlots
    /// internes fermés et lissage anti-crénelage strictement localisé à la frontière du contour.
    private static func analyzeBackgroundMatte(px: [UInt8], size: Int) -> SmoothMatteAnalysis? {
        let total = size * size
        let inv255: Float = 1.0 / 255.0

        // Zone squircle macOS standard : ~9.1% du canevas (~46.6 px sur 512)
        let rimSampleInset = Int(Float(size) * 0.114)
        let rimMax = size - 1 - rimSampleInset
        let cornerInset = Int(Float(size) * 0.172)
        let cornerSpan = max(4, Int(Float(size) * 0.024))

        // 0. Détecte d'abord si l'icône possède vraiment une carte squircle opaque ou si elle est déjà détourée (forme libre)
        var perimeterChecks = 0
        var perimeterOpaque = 0
        let edgeProbeStride = max(4, size / 40)
        for t in stride(from: cornerInset, through: size - 1 - cornerInset, by: edgeProbeStride) {
            for (pxX, pxY) in [(t, rimSampleInset), (t, rimMax), (rimSampleInset, t), (rimMax, t)] {
                perimeterChecks += 1
                if Float(px[(pxY * size + pxX) * 4 + 3]) * inv255 > 0.68 { perimeterOpaque += 1 }
            }
        }
        let innerCornerProbe = Int(Float(size) * 0.132)
        let cHigh = size - 1 - innerCornerProbe
        if Float(px[(innerCornerProbe * size + innerCornerProbe) * 4 + 3]) * inv255 > 0.68 { perimeterOpaque += 2 }
        if Float(px[(innerCornerProbe * size + cHigh) * 4 + 3]) * inv255 > 0.68 { perimeterOpaque += 2 }
        if Float(px[(cHigh * size + innerCornerProbe) * 4 + 3]) * inv255 > 0.68 { perimeterOpaque += 2 }
        if Float(px[(cHigh * size + cHigh) * 4 + 3]) * inv255 > 0.68 { perimeterOpaque += 2 }
        perimeterChecks += 8
        guard perimeterChecks > 0, Float(perimeterOpaque) / Float(perimeterChecks) >= 0.72 else {
            return nil
        }

        var rs = [Float]()
        var gs = [Float]()
        var bs = [Float]()
        rs.reserveCapacity(25)
        gs.reserveCapacity(25)
        bs.reserveCapacity(25)

        let half = size / 2
        var tlCorner = medianClusterSample(px: px, size: size, cx: cornerInset, cy: cornerInset, span: cornerSpan, inv255: inv255, rs: &rs, gs: &gs, bs: &bs)
        var trCorner = medianClusterSample(px: px, size: size, cx: size - 1 - cornerInset, cy: cornerInset, span: cornerSpan, inv255: inv255, rs: &rs, gs: &gs, bs: &bs)
        var blCorner = medianClusterSample(px: px, size: size, cx: cornerInset, cy: size - 1 - cornerInset, span: cornerSpan, inv255: inv255, rs: &rs, gs: &gs, bs: &bs)
        var brCorner = medianClusterSample(px: px, size: size, cx: size - 1 - cornerInset, cy: size - 1 - cornerInset, span: cornerSpan, inv255: inv255, rs: &rs, gs: &gs, bs: &bs)

        let topMid = medianClusterSample(px: px, size: size, cx: half, cy: rimSampleInset, span: cornerSpan, inv255: inv255, rs: &rs, gs: &gs, bs: &bs)
        let botMid = medianClusterSample(px: px, size: size, cx: half, cy: rimMax, span: cornerSpan, inv255: inv255, rs: &rs, gs: &gs, bs: &bs)
        let leftMid = medianClusterSample(px: px, size: size, cx: rimSampleInset, cy: half, span: cornerSpan, inv255: inv255, rs: &rs, gs: &gs, bs: &bs)
        let rightMid = medianClusterSample(px: px, size: size, cx: rimMax, cy: half, span: cornerSpan, inv255: inv255, rs: &rs, gs: &gs, bs: &bs)

        func cleanCorner(
            _ corner: (r: Float, g: Float, b: Float)?,
            adjA: (r: Float, g: Float, b: Float)?,
            adjB: (r: Float, g: Float, b: Float)?
        ) -> (r: Float, g: Float, b: Float)? {
            if let adjA, let adjB, perceptualColorDist(adjA, adjB) < 0.24 {
                let edgeAvg = ((adjA.r + adjB.r) * 0.5, (adjA.g + adjB.g) * 0.5, (adjA.b + adjB.b) * 0.5)
                if let c = corner, perceptualColorDist(c, edgeAvg) < 0.26 {
                    return c
                }
                return edgeAvg
            }
            return corner ?? adjA ?? adjB
        }

        tlCorner = cleanCorner(tlCorner, adjA: topMid, adjB: leftMid)
        trCorner = cleanCorner(trCorner, adjA: topMid, adjB: rightMid)
        blCorner = cleanCorner(blCorner, adjA: botMid, adjB: leftMid)
        brCorner = cleanCorner(brCorner, adjA: botMid, adjB: rightMid)

        let validAnchors = [tlCorner, trCorner, blCorner, brCorner, topMid, botMid, leftMid, rightMid].compactMap { $0 }
        guard !validAnchors.isEmpty else { return nil }

        let invAnchors = 1.0 / Float(validAnchors.count)
        let fallback = (
            r: validAnchors.reduce(Float(0)) { $0 + $1.r } * invAnchors,
            g: validAnchors.reduce(Float(0)) { $0 + $1.g } * invAnchors,
            b: validAnchors.reduce(Float(0)) { $0 + $1.b } * invAnchors
        )
        let tl = tlCorner ?? fallback
        let tr = trCorner ?? fallback
        let bl = blCorner ?? fallback
        let br = brCorner ?? fallback

        let cornerVals = [tl, tr, bl, br]
        var maxCornerSpread: Float = 0
        for i in 0..<4 {
            for j in (i + 1)..<4 {
                maxCornerSpread = max(maxCornerSpread, perceptualColorDist(cornerVals[i], cornerVals[j]))
            }
        }

        let uLUT = (size == pixelSize) ? cachedULUT512 : makeULUT(size: size)

        var ringMatches = 0
        var ringTotal = 0
        let step = max(3, size / 64)
        let spanStart = cornerInset
        let spanEnd = size - 1 - cornerInset
        if spanEnd > spanStart {
            for t in stride(from: spanStart, through: spanEnd, by: step) {
                for (pxX, pxY) in [(t, rimSampleInset), (t, rimMax), (rimSampleInset, t), (rimMax, t)] {
                    if let c = sampleNormalizedRGB(px: px, size: size, x: pxX, y: pxY, inv255: inv255) {
                        ringTotal += 1
                        let u = uLUT[pxX], v = uLUT[pxY]
                        let oneMinusU = 1.0 - u, oneMinusV = 1.0 - v
                        let wTL = oneMinusU * oneMinusV, wTR = u * oneMinusV, wBL = oneMinusU * v, wBR = u * v
                        let est = (
                            tl.r * wTL + tr.r * wTR + bl.r * wBL + br.r * wBR,
                            tl.g * wTL + tr.g * wTR + bl.g * wBL + br.g * wBR,
                            tl.b * wTL + tr.b * wTR + bl.b * wBL + br.b * wBR
                        )
                        if perceptualColorDist(c, est) < 0.20 {
                            ringMatches += 1
                        }
                    }
                }
            }
        }
        let ringMatchRatio = ringTotal == 0 ? 1.0 : Float(ringMatches) / Float(ringTotal)
        guard ringMatchRatio >= 0.45 else {
            return nil
        }

        // 2. Extraction RGB dé-prémultiplié et distance perceptuelle au carré au champ de fond (zéro sqrtf sur 262k px)
        var rgb = [Float](repeating: 0.0, count: total * 3)
        var bgDistSq = [Float](repeating: 1.0, count: total)

        px.withUnsafeBufferPointer { pxBuf in
            rgb.withUnsafeMutableBufferPointer { rgbBuf in
                bgDistSq.withUnsafeMutableBufferPointer { distBuf in
                    uLUT.withUnsafeBufferPointer { lutBuf in
                        let pxBase = pxBuf.baseAddress!
                        let rgbBase = rgbBuf.baseAddress!
                        let distBase = distBuf.baseAddress!
                        let lutBase = lutBuf.baseAddress!

                        for y in 0..<size {
                            let row = y * size
                            let v = lutBase[y]
                            let oneMinusV = 1.0 - v
                            let leftR = tl.r * oneMinusV + bl.r * v
                            let leftG = tl.g * oneMinusV + bl.g * v
                            let leftB = tl.b * oneMinusV + bl.b * v
                            let rightR = tr.r * oneMinusV + br.r * v
                            let rightG = tr.g * oneMinusV + br.g * v
                            let rightB = tr.b * oneMinusV + br.b * v

                            for x in 0..<size {
                                let idx = row + x
                                let off = idx * 4
                                let aByte = pxBase[off + 3]
                                if aByte <= 7 {
                                    distBase[idx] = 0.0
                                    continue
                                }
                                let r: Float, g: Float, b: Float
                                if aByte == 255 {
                                    r = Float(pxBase[off]) * inv255
                                    g = Float(pxBase[off + 1]) * inv255
                                    b = Float(pxBase[off + 2]) * inv255
                                } else {
                                    let invA = 1.0 / Float(aByte)
                                    r = min(1.0, Float(pxBase[off]) * invA)
                                    g = min(1.0, Float(pxBase[off + 1]) * invA)
                                    b = min(1.0, Float(pxBase[off + 2]) * invA)
                                }
                                let rgbOff = idx * 3
                                rgbBase[rgbOff] = r
                                rgbBase[rgbOff + 1] = g
                                rgbBase[rgbOff + 2] = b

                                let u = lutBase[x]
                                let oneMinusU = 1.0 - u
                                let bgR = leftR * oneMinusU + rightR * u
                                let bgG = leftG * oneMinusU + rightG * u
                                let bgB = leftB * oneMinusU + rightB * u
                                let dr = r - bgR, dg = g - bgG, db = b - bgB
                                let dl = 0.299 * dr + 0.587 * dg + 0.114 * db
                                let chromaSq = (dr - dl) * (dr - dl) + (dg - dl) * (dg - dl) + (db - dl) * (db - dl)
                                distBase[idx] = dl * dl * 0.90 + chromaSq * 1.45
                            }
                        }
                    }
                }
            }
        }

        let avgBGLum = (
            (0.2126 * tl.r + 0.7152 * tl.g + 0.0722 * tl.b)
            + (0.2126 * tr.r + 0.7152 * tr.g + 0.0722 * tr.b)
            + (0.2126 * bl.r + 0.7152 * bl.g + 0.0722 * bl.b)
            + (0.2126 * br.r + 0.7152 * br.g + 0.0722 * br.b)
        ) * 0.25
        var satSum: Float = 0
        for c in cornerVals {
            let mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b))
            satSum += mx > 0.001 ? ((mx - mn) / mx) : 0
        }
        let avgBGSat = satSum * 0.25
        let isBrightWhiteBG = (avgBGLum > 0.80 && avgBGSat < 0.10)
        let isPaleGrayBG = !isBrightWhiteBG && (avgBGLum > 0.66 && avgBGSat < 0.14)

        // Passe 1 adaptée à la luminosité du fond
        let isBackgroundOpt: [UInt8]? = px.withUnsafeBufferPointer { pxBuf in
            rgb.withUnsafeBufferPointer { rgbBuf in
                bgDistSq.withUnsafeBufferPointer { distBuf in
                    if isBrightWhiteBG {
                        let bg = runMatteFloodFill(
                            size: size, px: pxBuf, rgb: rgbBuf, bgDistSq: distBuf,
                            rimSampleInset: rimSampleInset, rimMax: rimMax, maxCornerSpread: maxCornerSpread,
                            isBrightWhiteBG: isBrightWhiteBG, isPaleGrayBG: isPaleGrayBG, avgBGLum: avgBGLum,
                            directDist: 0.072, gradDistMax: 0.105, stepSqMax: 0.011 * 0.011
                        )
                        return centerForegroundRatio(size: size, bgMask: bg, px: pxBuf) >= 0.045 ? bg : nil
                    } else if isPaleGrayBG {
                        let bg = runMatteFloodFill(
                            size: size, px: pxBuf, rgb: rgbBuf, bgDistSq: distBuf,
                            rimSampleInset: rimSampleInset, rimMax: rimMax, maxCornerSpread: maxCornerSpread,
                            isBrightWhiteBG: isBrightWhiteBG, isPaleGrayBG: isPaleGrayBG, avgBGLum: avgBGLum,
                            directDist: 0.135, gradDistMax: 0.215, stepSqMax: 0.016 * 0.016
                        )
                        return centerForegroundRatio(size: size, bgMask: bg, px: pxBuf) >= 0.055 ? bg : nil
                    } else {
                        let minFGThreshold: Float = avgBGLum < 0.42 ? 0.012 : 0.055
                        let bg = runMatteFloodFill(
                            size: size, px: pxBuf, rgb: rgbBuf, bgDistSq: distBuf,
                            rimSampleInset: rimSampleInset, rimMax: rimMax, maxCornerSpread: maxCornerSpread,
                            isBrightWhiteBG: isBrightWhiteBG, isPaleGrayBG: isPaleGrayBG, avgBGLum: avgBGLum,
                            directDist: 0.175, gradDistMax: 0.30, stepSqMax: 0.022 * 0.022
                        )
                        if centerForegroundRatio(size: size, bgMask: bg, px: pxBuf) >= minFGThreshold {
                            return bg
                        }
                        let strictBg = runMatteFloodFill(
                            size: size, px: pxBuf, rgb: rgbBuf, bgDistSq: distBuf,
                            rimSampleInset: rimSampleInset, rimMax: rimMax, maxCornerSpread: maxCornerSpread,
                            isBrightWhiteBG: isBrightWhiteBG, isPaleGrayBG: isPaleGrayBG, avgBGLum: avgBGLum,
                            directDist: 0.085, gradDistMax: 0.14, stepSqMax: 0.012 * 0.012
                        )
                        return centerForegroundRatio(size: size, bgMask: strictBg, px: pxBuf) >= minFGThreshold ? strictBg : nil
                    }
                }
            }
        }
        guard let isBackground = isBackgroundOpt else { return nil }

        // 4. Construction du matte haute précision sans allocation intermédiaire superflue :
        // Tout le fond détecté est effacé à 100% (1.0) et seule la frontière de 1–2 px reçoit un anti-crénelage doux.
        let maxIdx = size - 1
        var rawMatte = [Float](repeating: 0.0, count: total)
        var boundaryIndices = [Int32]()
        boundaryIndices.reserveCapacity(4096)

        px.withUnsafeBufferPointer { pxBuf in
            isBackground.withUnsafeBufferPointer { bgBuf in
                bgDistSq.withUnsafeBufferPointer { distBuf in
                    rawMatte.withUnsafeMutableBufferPointer { matteBuf in
                        let pxBase = pxBuf.baseAddress!
                        let bgBase = bgBuf.baseAddress!
                        let distBase = distBuf.baseAddress!
                        let matteBase = matteBuf.baseAddress!

                        for y in 0..<size {
                            let row = y * size
                            for x in 0..<size {
                                let idx = row + x
                                if bgBase[idx] != 0 {
                                    if pxBase[idx * 4 + 3] <= 20 {
                                        matteBase[idx] = 1.0
                                        continue
                                    }
                                    let touchesFG = (x > 0 && bgBase[idx - 1] == 0)
                                        || (x < maxIdx && bgBase[idx + 1] == 0)
                                        || (y > 0 && bgBase[idx - size] == 0)
                                        || (y < maxIdx && bgBase[idx + size] == 0)
                                    if touchesFG {
                                        if x > 0 && x < maxIdx && y > 0 && y < maxIdx {
                                            boundaryIndices.append(Int32(idx))
                                        }
                                        let dist = sqrtf(distBase[idx])
                                        let t = min(1.0, max(0.0, (dist - 0.04) * 6.25))
                                        let smooth = t * t * (3.0 - 2.0 * t)
                                        matteBase[idx] = 1.0 - smooth * 0.35
                                    } else {
                                        matteBase[idx] = 1.0
                                    }
                                } else {
                                    let touchesBG = (x > 0 && bgBase[idx - 1] != 0)
                                        || (x < maxIdx && bgBase[idx + 1] != 0)
                                        || (y > 0 && bgBase[idx - size] != 0)
                                        || (y < maxIdx && bgBase[idx + size] != 0)
                                    if touchesBG {
                                        if x > 0 && x < maxIdx && y > 0 && y < maxIdx {
                                            boundaryIndices.append(Int32(idx))
                                        }
                                        let dSq = distBase[idx]
                                        if dSq < 0.04 {
                                            let t = max(0.0, 1.0 - sqrtf(dSq) * 5.0)
                                            matteBase[idx] = t * t * 0.42
                                        }
                                    }
                                }
                            }
                        }

                        // 5. Adoucissement sous-pixellique localisé UNIQUEMENT sur les indices frontaliers (zéro copie 1 Mo de rawMatte)
                        if !boundaryIndices.isEmpty {
                            var smoothed = [Float](repeating: 0.0, count: boundaryIndices.count)
                            for i in 0..<boundaryIndices.count {
                                let idx = Int(boundaryIndices[i])
                                let sum = matteBase[idx] * 4.0
                                    + (matteBase[idx - 1] + matteBase[idx + 1] + matteBase[idx - size] + matteBase[idx + size]) * 2.0
                                    + (matteBase[idx - size - 1] + matteBase[idx - size + 1] + matteBase[idx + size - 1] + matteBase[idx + size + 1])
                                smoothed[i] = sum * (1.0 / 16.0)
                            }
                            for i in 0..<boundaryIndices.count {
                                matteBase[Int(boundaryIndices[i])] = smoothed[i]
                            }
                        }
                    }
                }
            }
        }

        return SmoothMatteAnalysis(
            matte: rawMatte,
            bilinearCorners: (tl, tr, bl, br),
            uLUT: uLUT,
            avgBGLuminance: avgBGLum,
            isSquircleCard: true
        )
    }

    /// Shader 512×512 haute précision : applique les apparences Sombre, Clair, Teinté et Transparent/Liquid Glass
    /// avec décontamination colorimétrique des contours et préservation de contraste.
    /// Retourne `true` lorsqu'une carte squircle a été détourée et nécessite le rognage fin du liseré externe Apple.
    @discardableResult
    private static func applyPixelStyleShader(
        _ px: inout [UInt8],
        size: Int,
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double),
        isPro: Bool
    ) -> Bool {
        let total = size * size
        let isGlassStyle = (style == .transparent || style == .clearLiquid || style == .clearDark || style == .frostedGlass)
        let isCrystalMode = style.usesCrystalGlassBackdrop(isPro: isPro)
        let needsMatte = isGlassStyle || isCrystalMode || style == .dark || style == .light
        let analysis = needsMatte ? analyzeBackgroundMatte(px: px, size: size) : nil
        let bgMatte = analysis?.matte ?? []

        let tintR = Float(tintRGB.r), tintG = Float(tintRGB.g), tintB = Float(tintRGB.b)
        let loR = tintR * 0.20, loG = tintG * 0.20, loB = tintB * 0.22
        let hiR = min(1.0, tintR * 0.86 + 0.26)
        let hiG = min(1.0, tintG * 0.86 + 0.26)
        let hiB = min(1.0, tintB * 0.86 + 0.28)
        let inv255: Float = 1.0 / 255.0
        let isPow2Size = (size & (size - 1)) == 0
        let sizeMask = size - 1
        let sizeShift = isPow2Size ? size.trailingZeroBitCount : 0
        let strippedBrightCard = (analysis?.avgBGLuminance ?? 0.0) > 0.68
        let liftDarkInkOnGlass = (style == .transparent || style == .clearLiquid || style == .clearDark || (isCrystalMode && style == .dark))
            && ((analysis?.avgBGLuminance ?? 0.0) > 0.70)
        let hasMatte = !bgMatte.isEmpty
        let shouldDecontaminate = (isGlassStyle || isCrystalMode) && analysis != nil
        let cornersOpt = analysis?.bilinearCorners
        let uLUTRef = analysis?.uLUT ?? []

        px.withUnsafeMutableBufferPointer { pxBuf in
            bgMatte.withUnsafeBufferPointer { matteBuf in
                uLUTRef.withUnsafeBufferPointer { uBuf in
                    pow074LUT.withUnsafeBufferPointer { p074Buf in
                        pow088LUT.withUnsafeBufferPointer { p088Buf in
                            let pxBase = pxBuf.baseAddress!
                            let matteBase = matteBuf.baseAddress
                            let uBase = uBuf.baseAddress
                            let p074Base = p074Buf.baseAddress!
                            let p088Base = p088Buf.baseAddress!

                            for idx in 0..<total {
                                let offset = idx * 4
                                let aByte = pxBase[offset + 3]
                                guard aByte > 5 else { continue }

                                var r: Float
                                var g: Float
                                var b: Float
                                var outA: Float
                                if aByte == 255 {
                                    r = Float(pxBase[offset]) * inv255
                                    g = Float(pxBase[offset + 1]) * inv255
                                    b = Float(pxBase[offset + 2]) * inv255
                                    outA = 1.0
                                } else {
                                    let a = Float(aByte) * inv255
                                    let invA = 1.0 / Float(aByte)
                                    r = min(1.0, Float(pxBase[offset]) * invA)
                                    g = min(1.0, Float(pxBase[offset + 1]) * invA)
                                    b = min(1.0, Float(pxBase[offset + 2]) * invA)
                                    outA = a
                                }

                                let bgW: Float = (hasMatte && matteBase != nil) ? matteBase![idx] : 0.0

                                // Décontamination colorimétrique des pixels de bordure semi-transparents :
                                // retire l'aura colorée héritée de l'ancien fond le long du contour détouré
                                if shouldDecontaminate, bgW > 0.04, bgW < 0.95, let corners = cornersOpt, let uBase {
                                    let pxXInt = isPow2Size ? (idx & sizeMask) : (idx % size)
                                    let pxYInt = isPow2Size ? (idx >> sizeShift) : (idx / size)
                                    let fgAlpha = max(0.22, 1.0 - bgW)
                                    let u = uBase[pxXInt]
                                    let v = uBase[pxYInt]
                                    let oneMinusU = 1.0 - u
                                    let oneMinusV = 1.0 - v
                                    let wTL = oneMinusU * oneMinusV
                                    let wTR = u * oneMinusV
                                    let wBL = oneMinusU * v
                                    let wBR = u * v
                                    let estBGR = corners.tl.r * wTL + corners.tr.r * wTR + corners.bl.r * wBL + corners.br.r * wBR
                                    let estBGG = corners.tl.g * wTL + corners.tr.g * wTR + corners.bl.g * wBL + corners.br.g * wBR
                                    let estBGB = corners.tl.b * wTL + corners.tr.b * wTR + corners.bl.b * wBL + corners.br.b * wBR
                                    let invFg = 1.0 / fgAlpha
                                    let unmixedR = min(1.0, max(0.0, (r - bgW * estBGR) * invFg))
                                    let unmixedG = min(1.0, max(0.0, (g - bgW * estBGG) * invFg))
                                    let unmixedB = min(1.0, max(0.0, (b - bgW * estBGB) * invFg))
                                    r = r * 0.22 + unmixedR * 0.78
                                    g = g * 0.22 + unmixedG * 0.78
                                    b = b * 0.22 + unmixedB * 0.78
                                }

                                let maxC = max(r, max(g, b))
                                let minC = min(r, min(g, b))
                                let sat = maxC > 0.001 ? ((maxC - minC) / maxC) : 0.0
                                let lum: Float = 0.2126 * r + 0.7152 * g + 0.0722 * b

                                switch style {
                                case .dark:
                                    if isCrystalMode {
                                        if bgW > 0.005 { outA *= (1.0 - bgW) }
                                        if liftDarkInkOnGlass && outA > 0.05 && lum < 0.46 && sat < 0.18 {
                                            let inkT = (1.0 - min(1.0, lum / 0.46)) * (1.0 - min(1.0, sat / 0.18))
                                            let targetW: Float = 0.88 - lum * 0.18
                                            r = r * (1.0 - inkT) + targetW * inkT
                                            g = g * (1.0 - inkT) + targetW * inkT
                                            b = b * (1.0 - inkT) + min(1.0, targetW + 0.03) * inkT
                                        }
                                    } else {
                                        let lumT = min(1.0, max(0.0, (lum - 0.56) / 0.30))
                                        let satT = 1.0 - min(1.0, max(0.0, (sat - 0.06) / 0.22))
                                        let t = max(bgW * lumT, lumT * satT)
                                        if t > 0.001 {
                                            let darkR: Float = 0.09 + (1.0 - lum) * 0.12
                                            let darkG: Float = 0.095 + (1.0 - lum) * 0.12
                                            let darkB: Float = 0.125 + (1.0 - lum) * 0.14
                                            let oneMinusT = 1.0 - t
                                            r = r * oneMinusT + darkR * t
                                            g = g * oneMinusT + darkG * t
                                            b = b * oneMinusT + darkB * t
                                        }
                                    }

                                case .light:
                                    if isCrystalMode {
                                        if bgW > 0.005 { outA *= (1.0 - bgW) }
                                    } else {
                                        let lumT = min(1.0, max(0.0, (0.28 - lum) / 0.24))
                                        let satT = 1.0 - min(1.0, max(0.0, (sat - 0.06) / 0.22))
                                        let t = max(bgW * lumT, lumT * satT)
                                        if t > 0.001 {
                                            let lightVal: Float = 0.94 - lum * 0.22
                                            let oneMinusT = 1.0 - t
                                            r = r * oneMinusT + lightVal * t
                                            g = g * oneMinusT + lightVal * t
                                            b = b * oneMinusT + (lightVal + 0.02) * t
                                        }
                                    }

                                case .tinted:
                                    let lumIdx = Int(min(4095.0, max(0.0, lum) * 4095.0 + 0.5))
                                    if isCrystalMode {
                                        if bgW > 0.005 { outA *= (1.0 - bgW) }
                                        let curve: Float
                                        if strippedBrightCard && lum < 0.26 && sat < 0.16 {
                                            curve = 0.88 - lum * 0.30
                                        } else {
                                            curve = min(1.0, max(0.32, p074Base[lumIdx]))
                                        }
                                        r = loR + (hiR - loR) * curve
                                        g = loG + (hiG - loG) * curve
                                        b = loB + (hiB - loB) * curve
                                    } else {
                                        let baseDarkR: Float = 0.04, baseDarkG: Float = 0.06, baseDarkB: Float = 0.10
                                        let curve = p088Base[lumIdx]
                                        r = baseDarkR + (tintR - baseDarkR) * curve
                                        g = baseDarkG + (tintG - baseDarkG) * curve
                                        b = baseDarkB + (tintB - baseDarkB) * curve
                                    }

                                case .monochrome:
                                    if isCrystalMode {
                                        if bgW > 0.005 { outA *= (1.0 - bgW) }
                                        let monoLum: Float
                                        if strippedBrightCard && lum < 0.26 && sat < 0.16 {
                                            monoLum = 0.90 - lum * 0.28
                                        } else {
                                            monoLum = min(1.0, max(0.24, (lum - 0.5) * 1.10 + 0.58))
                                        }
                                        r = monoLum * 0.96
                                        g = monoLum * 0.97
                                        b = monoLum
                                    } else {
                                        let contrasted = min(1.0, max(0.0, (lum - 0.5) * 1.16 + 0.52))
                                        r = contrasted * 0.96
                                        g = contrasted * 0.97
                                        b = contrasted
                                    }

                                case .transparent, .clearLiquid, .clearDark, .frostedGlass:
                                    if bgW > 0.005 {
                                        outA *= (1.0 - bgW)
                                    }
                                    if liftDarkInkOnGlass && outA > 0.05 && lum < 0.46 && sat < 0.18 {
                                        let inkT = (1.0 - min(1.0, lum / 0.46)) * (1.0 - min(1.0, sat / 0.18))
                                        let targetW: Float = 0.90 - lum * 0.18
                                        r = r * (1.0 - inkT) + targetW * inkT
                                        g = g * (1.0 - inkT) + targetW * inkT
                                        b = b * (1.0 - inkT) + min(1.0, targetW + 0.03) * inkT
                                    } else if style == .frostedGlass || style == .clearLiquid {
                                        r = min(1.0, r * 0.96 + 0.04)
                                        g = min(1.0, g * 0.96 + 0.04)
                                        b = min(1.0, b * 0.97 + 0.05)
                                    }

                                case .original, .classicApple, .system:
                                    break
                                }

                                let outA255 = outA * 255.0
                                pxBase[offset]     = UInt8(clamping: Int(r * outA255 + 0.5))
                                pxBase[offset + 1] = UInt8(clamping: Int(g * outA255 + 0.5))
                                pxBase[offset + 2] = UInt8(clamping: Int(b * outA255 + 0.5))
                                pxBase[offset + 3] = UInt8(clamping: Int(outA255 + 0.5))
                            }
                        }
                    }
                }
            }
        }
        return analysis?.isSquircleCard == true
    }

    struct AsyncRenderBatch: Sendable {
        let images: [String: CGImage]
        let newlyRendered: [String: CGImage]
        let miniThumbnails: [String: CGImage]
    }

    private static func makeMiniCGThumbnail(from cg: CGImage, targetPx: Int = 64) -> CGImage? {
        guard let cs = sRGBColorSpace,
              let ctx = CGContext(
                  data: nil,
                  width: targetPx,
                  height: targetPx,
                  bitsPerComponent: 8,
                  bytesPerRow: targetPx * 4,
                  space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetPx, height: targetPx))
        return ctx.makeImage()
    }

    /// Rendu asynchrone borné en arrière-plan avec consultation prioritaire du cache disque `IconsV2`
    /// (évite de re-exécuter le shader 512×512 pour les icônes déjà persistées au démarrage ou changement de thème).
    static func renderAsyncWithDiskCache(
        _ paths: [String],
        style: IconAppearanceStyle,
        tintKey: String,
        tintRGB: (r: Double, g: Double, b: Double) = (0.08, 0.54, 0.98),
        isPro: Bool = UserDefaults.standard.bool(forKey: PrefKey.isProUnlocked),
        miniTargetPaths: Set<String> = [],
        priority: TaskPriority = .utility,
        maxConcurrency: Int = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
    ) async -> AsyncRenderBatch {
        guard !paths.isEmpty else { return AsyncRenderBatch(images: [:], newlyRendered: [:], miniThumbnails: [:]) }
        var images: [String: CGImage] = [:]
        var newlyRendered: [String: CGImage] = [:]
        var miniThumbnails: [String: CGImage] = [:]
        images.reserveCapacity(paths.count)

        let workerLimit = max(1, min(maxConcurrency, paths.count))
        var nextIndex = 0

        await withTaskGroup(of: (String, CGImage?, CGImage?, Bool)?.self) { group in
            for _ in 0..<workerLimit {
                let path = paths[nextIndex]
                nextIndex += 1
                let wantsMini = miniTargetPaths.contains(path)
                group.addTask(priority: priority) {
                    guard !Task.isCancelled else { return nil }
                    return autoreleasepool {
                        guard !Task.isCancelled else { return nil }
                        if let cached = IconDiskCache.loadCGImage(for: path, style: style, tintKey: tintKey, isPro: isPro) {
                            let mini = wantsMini ? makeMiniCGThumbnail(from: cached) : nil
                            return (path, cached, mini, false)
                        }
                        guard !Task.isCancelled else { return nil }
                        let rendered = renderStyledHighResIcon(for: path, style: style, tintRGB: tintRGB, isPro: isPro)
                        let mini = (wantsMini ? rendered.flatMap { makeMiniCGThumbnail(from: $0) } : nil)
                        return (path, rendered, mini, true)
                    }
                }
            }

            while let result = await group.next() {
                if let (path, cg, mini, isNew) = result, let cg {
                    images[path] = cg
                    if let mini { miniThumbnails[path] = mini }
                    if isNew { newlyRendered[path] = cg }
                }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if nextIndex < paths.count {
                    let path = paths[nextIndex]
                    nextIndex += 1
                    let wantsMini = miniTargetPaths.contains(path)
                    group.addTask(priority: priority) {
                        guard !Task.isCancelled else { return nil }
                        return autoreleasepool {
                            guard !Task.isCancelled else { return nil }
                            if let cached = IconDiskCache.loadCGImage(for: path, style: style, tintKey: tintKey, isPro: isPro) {
                                let mini = wantsMini ? makeMiniCGThumbnail(from: cached) : nil
                                return (path, cached, mini, false)
                            }
                            guard !Task.isCancelled else { return nil }
                            let rendered = renderStyledHighResIcon(for: path, style: style, tintRGB: tintRGB, isPro: isPro)
                            let mini = (wantsMini ? rendered.flatMap { makeMiniCGThumbnail(from: $0) } : nil)
                            return (path, rendered, mini, true)
                        }
                    }
                }
            }
        }
        return AsyncRenderBatch(images: images, newlyRendered: newlyRendered, miniThumbnails: miniThumbnails)
    }

    /// Prépare uniquement le cache disque pour les pages lointaines sans épingler des centaines de bitmaps 512×512 en RAM.
    static func warmDiskCacheAsync(
        _ paths: [String],
        style: IconAppearanceStyle,
        tintKey: String,
        tintRGB: (r: Double, g: Double, b: Double) = (0.08, 0.54, 0.98),
        isPro: Bool = UserDefaults.standard.bool(forKey: PrefKey.isProUnlocked),
        maxConcurrency: Int = 2
    ) async {
        guard !paths.isEmpty, let folder = IconDiskCache.folderURL(style: style, tintKey: tintKey, isPro: isPro) else { return }
        let missingOnDisk = paths.filter { !IconDiskCache.hasCachedFile(for: $0, style: style, tintKey: tintKey, isPro: isPro) }
        guard !missingOnDisk.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let workerLimit = max(1, min(maxConcurrency, missingOnDisk.count))
        var nextIndex = 0
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workerLimit {
                let path = missingOnDisk[nextIndex]
                nextIndex += 1
                group.addTask(priority: .background) {
                    guard !Task.isCancelled else { return }
                    autoreleasepool {
                        guard !Task.isCancelled else { return }
                        if let cg = renderStyledHighResIcon(for: path, style: style, tintRGB: tintRGB, isPro: isPro) {
                            let url = folder.appendingPathComponent(IconDiskCache.hexFilename(for: path))
                            IconDiskCache.writePNG(cg, to: url)
                        }
                    }
                }
            }
            while await group.next() != nil {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if nextIndex < missingOnDisk.count {
                    let path = missingOnDisk[nextIndex]
                    nextIndex += 1
                    group.addTask(priority: .background) {
                        guard !Task.isCancelled else { return }
                        autoreleasepool {
                            guard !Task.isCancelled else { return }
                            if let cg = renderStyledHighResIcon(for: path, style: style, tintRGB: tintRGB, isPro: isPro) {
                                let url = folder.appendingPathComponent(IconDiskCache.hexFilename(for: path))
                                IconDiskCache.writePNG(cg, to: url)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Rendu asynchrone borné en arrière-plan (annulable à chaque icône si l'utilisateur change de thème)
    static func renderAsync(
        _ paths: [String],
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double) = (0.08, 0.54, 0.98),
        isPro: Bool = UserDefaults.standard.bool(forKey: PrefKey.isProUnlocked),
        maxConcurrency: Int = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
    ) async -> [String: CGImage] {
        let tintKey = UserDefaults.standard.string(forKey: PrefKey.tintedIconColor) ?? "blue"
        return await renderAsyncWithDiskCache(
            paths,
            style: style,
            tintKey: tintKey,
            tintRGB: tintRGB,
            isPro: isPro,
            maxConcurrency: maxConcurrency
        ).images
    }

    /// Rend chaque icône en parallèle multi-cœur en arrière-plan à 512×512 pour un démarrage et un changement de style fluides
    static func render(
        _ paths: [String],
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double) = (0.08, 0.54, 0.98),
        isPro: Bool = UserDefaults.standard.bool(forKey: PrefKey.isProUnlocked)
    ) -> [String: CGImage] {
        guard !paths.isEmpty else { return [:] }
        var output: [String: CGImage] = [:]
        output.reserveCapacity(paths.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: paths.count) { index in
            let path = paths[index]
            autoreleasepool {
                if let cg = renderStyledHighResIcon(for: path, style: style, tintRGB: tintRGB, isPro: isPro) {
                    lock.lock()
                    output[path] = cg
                    lock.unlock()
                }
            }
        }
        return output
    }

    static func render(_ paths: [String], original: Bool) -> [String: CGImage] {
        render(paths, style: original ? .original : .system)
    }

    static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        let length = CFDataGetLength(data)
        var index = 3
        while index < length {
            if bytes[index] > 12 { return false }
            index += 4 * 37
        }
        return true
    }
}

// MARK: - Noms d'applications Apple localisés selon la langue de l'app

nonisolated enum AppleAppLocalizer {
    private static let frNames: [String: String] = [
        "com.apple.systempreferences": "Réglages Système",
        "com.apple.preferences.softwareupdate": "Mise à jour de logiciels",
        "com.apple.ical": "Calendrier",
        "com.apple.music": "Musique",
        "com.apple.preview": "Aperçu",
        "com.apple.activitymonitor": "Moniteur d'activité",
        "com.apple.audio.audiomidisetup": "Configuration audio et MIDI",
        "com.apple.chess": "Échecs",
        "com.apple.calculator": "Calculette",
        "com.apple.clock": "Horloge",
        "com.apple.ibooksx": "Livres",
        "com.apple.maps": "Plans",
        "com.apple.weather": "Météo",
        "com.apple.shortcuts": "Raccourcis",
        "com.apple.voicememos": "Dictaphone",
        "com.apple.reminders": "Rappels",
        "com.apple.home": "Maison",
        "com.apple.findmy": "Localiser",
        "com.apple.diskutility": "Utilitaire de disque",
        "com.apple.keychainaccess": "Trousseau d'accès",
        "com.apple.systemprofiler": "Informations système",
        "com.apple.screenshot.launcher": "Capture d'écran",
        "com.apple.screencapture": "Capture d'écran",
        "com.apple.migrationassistant": "Assistant migration",
        "com.apple.bluetoothfileexchange": "Échange de fichiers Bluetooth",
        "com.apple.airport.airportutility": "Utilitaire AirPort",
        "com.apple.colorsyncutility": "Utilitaire ColorSync",
        "com.apple.digitalcolormeter": "Colorimètre numérique",
        "com.apple.scripteditor2": "Éditeur de script",
        "com.apple.print.printerproxy": "Centre d'impression",
        "com.apple.printcenter": "Centre d'impression",
        "com.apple.image_capture": "Transfert d'images",
        "com.apple.dictionary": "Dictionnaire",
        "com.apple.stickies": "Aide-mémoire",
        "com.apple.stocks": "Bourse",
        "com.apple.fontbook": "Livre des polices",
        "com.apple.voiceoverutility": "Utilitaire VoiceOver",
        "com.apple.passwords": "Mots de passe",
        "com.apple.news": "News",
        "com.apple.quicktimeplayerx": "QuickTime Player",
        "com.apple.backup.launcher": "Time Machine",
        "com.apple.addressbook": "Contacts",
        "com.apple.automator": "Automator",
        "com.apple.textedit": "TextEdit",
        "com.apple.notes": "Notes",
        "com.apple.photos": "Photos",
        "com.apple.mobilesms": "Messages",
        "com.apple.mail": "Mail",
        "com.apple.safari": "Safari",
        "com.apple.facetime": "FaceTime",
        "com.apple.terminal": "Terminal",
        "com.apple.console": "Console",
        "com.apple.appstore": "App Store",
        "com.apple.tv": "TV",
        "com.apple.podcasts": "Podcasts",
        "com.apple.freeform": "Freeform",
        "com.apple.grapher": "Grapher",
        "com.apple.photobooth": "Photo Booth",
        "com.apple.launchpad.launcher": "Apps"
    ]

    private static let frByEnglishName: [String: String] = [
        "system settings": "Réglages Système",
        "system preferences": "Réglages Système",
        "calendar": "Calendrier",
        "music": "Musique",
        "preview": "Aperçu",
        "activity monitor": "Moniteur d'activité",
        "audio midi setup": "Configuration audio et MIDI",
        "chess": "Échecs",
        "calculator": "Calculette",
        "clock": "Horloge",
        "books": "Livres",
        "maps": "Plans",
        "weather": "Météo",
        "shortcuts": "Raccourcis",
        "voice memos": "Dictaphone",
        "reminders": "Rappels",
        "home": "Maison",
        "find my": "Localiser",
        "disk utility": "Utilitaire de disque",
        "keychain access": "Trousseau d'accès",
        "system information": "Informations système",
        "screenshot": "Capture d'écran",
        "migration assistant": "Assistant migration",
        "bluetooth file exchange": "Échange de fichiers Bluetooth",
        "airport utility": "Utilitaire AirPort",
        "colorsync utility": "Utilitaire ColorSync",
        "digital color meter": "Colorimètre numérique",
        "script editor": "Éditeur de script",
        "print center": "Centre d'impression",
        "image capture": "Transfert d'images",
        "dictionary": "Dictionnaire",
        "stickies": "Aide-mémoire",
        "stocks": "Bourse",
        "font book": "Livre des polices",
        "voiceover utility": "Utilitaire VoiceOver",
        "passwords": "Mots de passe"
    ]

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var localizedNameCache: [String: String] = [:]

    static func clearCache() {
        cacheLock.lock()
        localizedNameCache.removeAll(keepingCapacity: true)
        cacheLock.unlock()
    }

    nonisolated static func warm(apps: [AppInfo], languageCode: String) {
        let lang = languageCode.lowercased()
        for app in apps {
            _ = localizedName(for: app, languageCode: lang)
        }
    }

    static func localizedName(for app: AppInfo, languageCode: String) -> String {
        let lang = languageCode.lowercased()
        let isAppleApp = (app.bundleID?.lowercased().hasPrefix("com.apple.") == true)
            || app.id.hasPrefix("/System/Applications")
        guard isAppleApp else { return app.name }

        let cacheKey = "\(app.id)|\(lang)"
        cacheLock.lock()
        if let cached = localizedNameCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let resolved = computeLocalizedName(for: app, lang: lang)
        cacheLock.lock()
        localizedNameCache[cacheKey] = resolved
        cacheLock.unlock()
        return resolved
    }

    private static func computeLocalizedName(for app: AppInfo, lang: String) -> String {
        // 1. Table intégrée en mémoire O(1) pour le français (évite 3× appels disque InfoPlist.strings par app Apple)
        if lang == "fr" {
            if let bid = app.normalizedBundleID, let mapped = frNames[bid] {
                return mapped
            }
            if let mapped = frByEnglishName[app.normalizedName] {
                return mapped
            }
        }

        let lprojCandidates: [String]
        switch lang {
        case "fr": lprojCandidates = ["fr", "fr_FR", "French"]
        case "en": lprojCandidates = ["en", "en_US", "en_GB", "English"]
        case "es": lprojCandidates = ["es", "es_ES", "es_419", "Spanish"]
        case "de": lprojCandidates = ["de", "de_DE", "German"]
        case "it": lprojCandidates = ["it", "it_IT", "Italian"]
        case "pt": lprojCandidates = ["pt", "pt_PT", "pt_BR", "Portuguese"]
        default:   lprojCandidates = [lang, "\(lang)_\(lang.uppercased())"]
        }

        // 2. Lecture directe depuis <App>.app/Contents/Resources/<lang>.lproj/InfoPlist.strings
        let resourcesDir = app.url.appendingPathComponent("Contents/Resources", isDirectory: true)
        for code in lprojCandidates {
            let stringsURL = resourcesDir.appendingPathComponent("\(code).lproj/InfoPlist.strings")
            if let dict = NSDictionary(contentsOf: stringsURL) as? [String: Any] {
                if let display = dict["CFBundleDisplayName"] as? String, !display.isEmpty {
                    return display
                }
                if let bundleName = dict["CFBundleName"] as? String, !bundleName.isEmpty {
                    return bundleName
                }
            }
        }

        return app.name
    }
}

// MARK: - Noms de catégories

enum CategoryNames {
    private static let knownKeys: Set<String> = [
        "business", "developer-tools", "education", "entertainment", "finance",
        "games", "graphics-design", "healthcare-fitness", "lifestyle", "medical",
        "music", "news", "photography", "productivity", "reference",
        "social-networking", "sports", "travel", "utilities", "video",
        "weather", "books", "kids"
    ]

    static func title(for key: String) -> String {
        if knownKeys.contains(key) {
            return loc("app_cat.\(key)")
        }
        return key.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
