import AppKit
import CoreServices
import ImageIO
import SwiftUI

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

    init(
        id: String,
        url: URL,
        resolvedPath: String,
        name: String,
        bundleID: String?,
        category: String?,
        dateAdded: Date?,
        lastUsed: Date?
    ) {
        self.id = id
        self.url = url
        self.resolvedPath = resolvedPath
        self.name = name
        self.normalizedName = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        self.bundleID = bundleID
        self.normalizedBundleID = bundleID?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        self.category = category
        self.dateAdded = dateAdded
        self.lastUsed = lastUsed
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

    static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    static func scan(sources: [String]) -> [AppInfo] {
        let manager = FileManager.default
        let ownBundleID = Bundle.main.bundleIdentifier
        var seenPaths = Set<String>()
        var seenBundles = Set<String>()
        var result: [AppInfo] = []

        func visit(_ directory: URL, depth: Int) {
            guard let entries = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if entry.pathExtension.lowercased() == "app" {
                    let resolved = entry.resolvingSymlinksInPath().standardizedFileURL.path
                    guard seenPaths.insert(resolved).inserted, let info = makeInfo(entry, resolvedPath: resolved) else { continue }
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
        return result
    }

    static func makeInfo(_ url: URL, resolvedPath: String) -> AppInfo? {
        let standardized = url.standardizedFileURL
        let plist = infoDictionary(for: standardized)
        var name = FileManager.default.displayName(atPath: standardized.path)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        if name.isEmpty { name = standardized.deletingPathExtension().lastPathComponent }

        var dateAdded: Date?
        var lastUsed: Date?
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, standardized as CFURL) {
            dateAdded = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        }
        if dateAdded == nil {
            dateAdded = (try? standardized.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
        }

        return AppInfo(
            id: standardized.path,
            url: standardized,
            resolvedPath: resolvedPath,
            name: name,
            bundleID: plist?["CFBundleIdentifier"] as? String,
            category: plist?["LSApplicationCategoryType"] as? String,
            dateAdded: dateAdded,
            lastUsed: lastUsed
        )
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
    private var sources: [DispatchSourceFileSystemObject] = []
    var onChange: (() -> Void)?

    func watch(_ paths: [String]) {
        stop()
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
            sources.append(source)
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }
}

// MARK: - Icônes (pré-rendu en arrière-plan, comme l'AppIconRepository de LaunchOS)

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var images: [String: NSImage] = [:]
    private var fallbackCachedPaths: Set<String> = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.images.removeAll(keepingCapacity: false)
            self.fallbackCachedPaths.removeAll(keepingCapacity: false)
        }
        source.resume()
        self.memoryPressureSource = source
    }

    /// Style courant (lu une fois par accès : changer le réglage vide le cache).
    var useOriginalColors: Bool { currentAppearanceStyle != .system }

    var currentAppearanceStyle: IconAppearanceStyle {
        let isPro = UserDefaults.standard.bool(forKey: PrefKey.isProUnlocked)
        if UserDefaults.standard.bool(forKey: PrefKey.tintedIcons) && isPro {
            return .tinted
        }
        let raw = UserDefaults.standard.string(forKey: PrefKey.iconStyle) ?? "original"
        let parsed = IconAppearanceStyle(rawValue: raw) ?? .original
        if parsed.requiresPro && !isPro {
            return .original
        }
        return parsed
    }

    var activeTintKey: String {
        UserDefaults.standard.string(forKey: PrefKey.tintedIconColor) ?? "blue"
    }

    var activeTintRGB: (r: Double, g: Double, b: Double) {
        switch activeTintKey {
        case "graphite": return (0.78, 0.78, 0.78)
        case "purple": return (0.65, 0.42, 1.0)
        case "orange": return (1.0, 0.56, 0.14)
        case "mint": return (0.18, 0.85, 0.68)
        case "rose": return (1.0, 0.32, 0.56)
        case "gold": return (0.98, 0.78, 0.22)
        default: return (0.08, 0.54, 0.98)
        }
    }

    var activeTintColor: Color {
        let rgb = activeTintRGB
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    func icon(for path: String) -> NSImage {
        if let cached = images[path] {
            if fallbackCachedPaths.contains(path) {
                return cached
            }
            let maxPx = cached.representations.map(\.pixelsWide).max() ?? 0
            if maxPx >= IconRenderer.pixelSize {
                return cached
            }
        }

        let style = currentAppearanceStyle
        let tintRGB = activeTintRGB
        if !path.hasPrefix("web:") && !path.hasPrefix("shortcut:"),
           CustomIconManager.shared.hasOverride(for: path) {
            let appName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if let customImg = CustomAppIconRenderer.renderIcon(
                for: path,
                bundleID: nil,
                name: appName,
                style: style,
                tintColor: activeTintColor,
                pixelSize: 256
            ) {
                images[path] = customImg
                fallbackCachedPaths.remove(path)
                return customImg
            }
        }

        // Rendu haute résolution 512×512 Retina (apps & tuiles personnalisées)
        if let cg = IconRenderer.renderStyledHighResIcon(for: path, style: style, tintRGB: tintRGB) {
            let hdImage = CustomAppIconRenderer.wrapCGImageAsRetinaNSImage(cg)
            images[path] = hdImage
            fallbackCachedPaths.remove(path)
            return hdImage
        }

        let fallback = IconRenderer.sourceIcon(for: path, original: useOriginalColors)
        fallback.size = NSSize(width: 256, height: 256)
        images[path] = fallback
        fallbackCachedPaths.insert(path)
        return fallback
    }

    func contains(_ path: String) -> Bool {
        guard let cached = images[path] else { return false }
        if fallbackCachedPaths.contains(path) { return true }
        let maxPx = cached.representations.map(\.pixelsWide).max() ?? 0
        return maxPx >= IconRenderer.pixelSize
    }

    func store(_ rendered: [String: CGImage], forStyle expectedStyle: IconAppearanceStyle? = nil, tintKey expectedTintKey: String? = nil) {
        let style = currentAppearanceStyle
        if let expectedStyle, expectedStyle != style { return }
        if style == .tinted, let expectedTintKey, expectedTintKey != activeTintKey { return }
        for (path, cgImage) in rendered where images[path] == nil {
            if CustomIconManager.shared.hasOverride(for: path) { continue }
            images[path] = CustomAppIconRenderer.wrapCGImageAsRetinaNSImage(cgImage)
            fallbackCachedPaths.remove(path)
        }
    }

    func invalidate(_ paths: [String]) {
        for path in paths {
            images[path] = nil
            fallbackCachedPaths.remove(path)
        }
    }

    func removeAll() {
        images.removeAll()
        fallbackCachedPaths.removeAll()
    }
}

nonisolated enum IconRenderer {
    /// Résolution Retina haute densité 512×512 pixels physiques (pour affichage net jusqu'à 256pt @2x)
    static let pixelSize = 512
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

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
        let copy = (icon.copy() as? NSImage) ?? icon
        copy.size = NSSize(width: targetSize, height: targetSize)

        var proposedRect = NSRect(x: 0, y: 0, width: targetSize, height: targetSize)
        if let directCG = copy.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        ), directCG.width >= 256, !isBlank(directCG) {
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
        tintRGB: (r: Double, g: Double, b: Double)
    ) -> CGImage? {
        let preferOriginal = (style != .system)
        let primarySource = sourceIcon(for: path, original: preferOriginal)
        var rawCG = rasterizeNSImageHighRes(primarySource, targetSize: pixelSize)

        if rawCG == nil || (rawCG.map(isBlank) ?? true) {
            let wsFallback = NSWorkspace.shared.icon(forFile: path)
            wsFallback.size = NSSize(width: pixelSize, height: pixelSize)
            rawCG = rasterizeNSImageHighRes(wsFallback, targetSize: pixelSize)
        }
        guard let validCG = rawCG else { return nil }
        return normalizeAndStyleCGImage(
            validCG,
            style: style,
            tintRGB: tintRGB,
            forceSquircleClip: false
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
        forceSquircleClip: Bool
    ) -> CGImage? {
        let size = pixelSize
        guard let cs = sRGBColorSpace else { return sourceCG }

        // 1. Lecture des pixels sources en 512×512 pour détecter la boîte englobante visible (alphaBounds)
        var srcPixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let srcCtx = CGContext(
            data: &srcPixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return sourceCG }
        srcCtx.interpolationQuality = .high
        srcCtx.draw(sourceCG, in: CGRect(x: 0, y: 0, width: size, height: size))

        var minX = size, minY = size, maxX = 0, maxY = 0
        for y in 0..<size {
            let row = y * size * 4
            for x in 0..<size {
                if srcPixels[row + x * 4 + 3] > 24 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        // Cadre squircle standard macOS : 81.6% de la toile 512×512 (soit 418×418 px centré, marge = 47 px)
        let standardInset: CGFloat = CGFloat(size) * 0.091
        let standardBody: CGFloat = CGFloat(size) - standardInset * 2
        let targetBodyRect = CGRect(x: standardInset, y: standardInset, width: standardBody, height: standardBody)
        let bodySquirclePath = createAppleSquirclePath(in: targetBodyRect, cornerRatio: 0.225)
        // Rognage ultra-propre de 5 px le long de la courbe exacte d'Apple pour ôter l'ancien biseau/liseré externe
        let fgRimInset = CGFloat(size) * 0.0105
        let fgInnerTrimRect = targetBodyRect.insetBy(dx: fgRimInset, dy: fgRimInset)
        let fgInnerTrimPath = createAppleSquirclePath(in: fgInnerTrimRect, cornerRatio: 0.225)

        let visibleW = maxX >= minX ? CGFloat(maxX - minX + 1) : standardBody
        let visibleH = maxY >= minY ? CGFloat(maxY - minY + 1) : standardBody
        let maxVisibleDim = max(visibleW, visibleH)

        // Si l'icône déborde des marges standards (> 87% du canevas, ex. Wallper ou image plein cadre)
        // ou si elle est trop petite (< 72%), on la recadre proportionnellement dans le squircle standard
        let needsRescale = forceSquircleClip || maxVisibleDim > CGFloat(size) * 0.87 || maxVisibleDim < CGFloat(size) * 0.72
        let needsCornerClip = forceSquircleClip || maxVisibleDim > CGFloat(size) * 0.87

        var normPixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let normCtx = CGContext(
            data: &normPixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return sourceCG }
        normCtx.interpolationQuality = .high

        if needsCornerClip {
            normCtx.addPath(bodySquirclePath)
            normCtx.clip()
        }

        if needsRescale && maxVisibleDim > 0 {
            let scale = standardBody / maxVisibleDim
            let centerX = CGFloat(minX + maxX) * 0.5
            let centerY = CGFloat(size) - CGFloat(minY + maxY) * 0.5
            let drawW = CGFloat(size) * scale
            let drawH = CGFloat(size) * scale
            let drawX = CGFloat(size) * 0.5 - centerX * scale
            let drawY = CGFloat(size) * 0.5 - centerY * scale
            normCtx.draw(sourceCG, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        } else {
            normCtx.draw(sourceCG, in: CGRect(x: 0, y: 0, width: size, height: size))
        }

        // 2. Application du filtre de style pixel par pixel en 512×512 (détourage haute précision + décontamination des bords)
        var strippedSquircleCard = false
        if style != .original && style != .system && style != .classicApple {
            strippedSquircleCard = applyPixelStyleShader(&normPixels, size: size, style: style, tintRGB: tintRGB)
        }

        guard let styledCG = normCtx.makeImage() else { return sourceCG }

        // 3. Composition finale : socle Liquid Glass continu + reflets caustiques + contour spéculaire multicouche
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
        let isGlassStyle = (style == .transparent || style == .clearLiquid || style == .clearDark || style == .frostedGlass)

        if isGlassStyle {
            // Ombre portée douce sous le squircle continu
            finalCtx.saveGState()
            finalCtx.setShadow(
                offset: CGSize(width: 0, height: -fSize * 0.012),
                blur: fSize * 0.030,
                color: CGColor(gray: 0, alpha: style == .transparent ? 0.16 : 0.24)
            )
            finalCtx.addPath(bodySquirclePath)
            let baseFill: CGColor
            switch style {
            case .transparent:
                baseFill = CGColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 0.075)
            case .clearLiquid:
                baseFill = CGColor(red: 0.86, green: 0.92, blue: 1.0, alpha: 0.15)
            case .clearDark:
                baseFill = CGColor(red: 0.09, green: 0.11, blue: 0.19, alpha: 0.56)
            case .frostedGlass:
                baseFill = CGColor(red: 0.91, green: 0.94, blue: 1.0, alpha: 0.36)
            default:
                baseFill = CGColor(red: 1, green: 1, blue: 1, alpha: 0.12)
            }
            finalCtx.setFillColor(baseFill)
            finalCtx.fillPath()
            finalCtx.restoreGState()

            // Clip au squircle continu d'Apple
            finalCtx.saveGState()
            finalCtx.addPath(bodySquirclePath)
            finalCtx.clip()

            // Dégradé vertical de profondeur vitrée
            let glassGradColors: CFArray
            switch style {
            case .clearDark:
                glassGradColors = [
                    CGColor(red: 0.18, green: 0.21, blue: 0.34, alpha: 0.22),
                    CGColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 0.10)
                ] as CFArray
            case .frostedGlass:
                glassGradColors = [
                    CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24),
                    CGColor(red: 0.84, green: 0.89, blue: 1.0, alpha: 0.06)
                ] as CFArray
            default:
                glassGradColors = [
                    CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: style == .clearLiquid ? 0.18 : 0.11),
                    CGColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 0.02)
                ] as CFArray
            }
            if let glassGrad = CGGradient(colorsSpace: cs, colors: glassGradColors, locations: [0.0, 1.0]) {
                finalCtx.drawLinearGradient(
                    glassGrad,
                    start: CGPoint(x: targetBodyRect.midX, y: targetBodyRect.maxY),
                    end: CGPoint(x: targetBodyRect.midX, y: targetBodyRect.minY),
                    options: []
                )
            }

            // Reflet caustique diagonal subtil en verre cristal sur la tuile
            let sheenColors = [
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.10 : 0.22),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.00),
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.05 : 0.10)
            ] as CFArray
            if let sheenGrad = CGGradient(colorsSpace: cs, colors: sheenColors, locations: [0.0, 0.46, 1.0]) {
                finalCtx.drawLinearGradient(
                    sheenGrad,
                    start: CGPoint(x: targetBodyRect.minX, y: targetBodyRect.maxY),
                    end: CGPoint(x: targetBodyRect.maxX, y: targetBodyRect.minY),
                    options: []
                )
            }

            // Icône détourée et décontaminée, rognée avec la courbe exacte d'Apple (~5 px en retrait du biseau vitré)
            // afin qu'aucune bordure sombre/cyan d'origine ne déborde sous la bordure Liquid Glass
            finalCtx.saveGState()
            if strippedSquircleCard {
                finalCtx.addPath(fgInnerTrimPath)
                finalCtx.clip()
            }
            finalCtx.draw(styledCG, in: CGRect(x: 0, y: 0, width: fSize, height: fSize))
            finalCtx.restoreGState()

            // Contour automatique Liquid Glass continu (zéro encoche ni cassure) :
            // Biseau spéculaire interne continu en dégradé 4 points (Liquid Glass Apple)
            finalCtx.saveGState()
            let strokePath = CGMutablePath()
            // Tracé strictement contenu dans le squircle (rayon réduit de la moitié de l'épaisseur)
            let rimWidth = max(2.2, fSize * 0.0068)
            let insetRimPath = createAppleSquirclePath(
                in: targetBodyRect.insetBy(dx: rimWidth * 0.5, dy: rimWidth * 0.5),
                cornerRatio: 0.225
            )
            strokePath.addPath(insetRimPath)
            let rimColors = [
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.44 : 0.82),
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.14 : 0.24),
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.10 : 0.16),
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.30 : 0.54)
            ] as CFArray
            if let rimGrad = CGGradient(colorsSpace: cs, colors: rimColors, locations: [0.0, 0.36, 0.68, 1.0]) {
                finalCtx.addPath(strokePath)
                finalCtx.setLineWidth(rimWidth)
                finalCtx.setLineCap(.round)
                finalCtx.setLineJoin(.round)
                finalCtx.replacePathWithStrokedPath()
                finalCtx.clip()
                finalCtx.drawLinearGradient(
                    rimGrad,
                    start: CGPoint(x: targetBodyRect.minX, y: targetBodyRect.maxY),
                    end: CGPoint(x: targetBodyRect.maxX, y: targetBodyRect.minY),
                    options: []
                )
            }
            finalCtx.restoreGState()
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

    /// Analyse et détoure automatiquement le fond des icônes pour les modes Transparent / Liquid Glass.
    /// Combine détection de forme libre vs carte squircle, modélisation multi-ancres avec rejet d'anomalies,
    /// flood-fill double critère (teinte/luminance perceptuelle + continuité de dégradé), nettoyage des îlots
    /// internes fermés et lissage anti-crénelage strictement localisé à la frontière du contour.
    private static func analyzeBackgroundMatte(px: [UInt8], size: Int) -> SmoothMatteAnalysis? {
        let total = size * size
        let inv255: Float = 1.0 / 255.0

        // Zone squircle macOS standard : ~9.1% du canevas (~46.6 px sur 512)
        // Avec cornerRatio=0.225, l'apex du coin arrondi se trouve à ~14.6% (~75 px) ;
        // on échantillonne donc les coins à 17.2% (~88 px) et les milieux de bords à 11.4% (~58 px).
        let rimSampleInset = Int(Float(size) * 0.114)
        let rimMax = size - 1 - rimSampleInset
        let cornerInset = Int(Float(size) * 0.172)
        let cornerSpan = max(4, Int(Float(size) * 0.024))

        @inline(__always)
        func sampleRGB(x: Int, y: Int) -> (r: Float, g: Float, b: Float)? {
            guard x >= 0, x < size, y >= 0, y < size else { return nil }
            let off = (y * size + x) * 4
            let a = Float(px[off + 3]) * inv255
            guard a > 0.72 else { return nil }
            let invA = 1.0 / (255.0 * a)
            return (
                min(1.0, Float(px[off]) * invA),
                min(1.0, Float(px[off + 1]) * invA),
                min(1.0, Float(px[off + 2]) * invA)
            )
        }

        // 0. Détecte d'abord si l'icône possède vraiment une carte squircle opaque ou si elle est déjà détourée (forme libre)
        var perimeterChecks = 0
        var perimeterOpaque = 0
        let edgeProbeStride = max(4, size / 40)
        for t in stride(from: cornerInset, through: size - 1 - cornerInset, by: edgeProbeStride) {
            for (pxX, pxY) in [(t, rimSampleInset), (t, rimMax), (rimSampleInset, t), (rimMax, t)] {
                perimeterChecks += 1
                let a = Float(px[(pxY * size + pxX) * 4 + 3]) * inv255
                if a > 0.68 { perimeterOpaque += 1 }
            }
        }
        // Inclut aussi les 4 coins internes du squircle pour distinguer une forme ronde/libre d'une carte squircle
        let innerCornerProbe = Int(Float(size) * 0.132)
        for (cx, cy) in [
            (innerCornerProbe, innerCornerProbe),
            (size - 1 - innerCornerProbe, innerCornerProbe),
            (innerCornerProbe, size - 1 - innerCornerProbe),
            (size - 1 - innerCornerProbe, size - 1 - innerCornerProbe)
        ] {
            perimeterChecks += 2
            let a = Float(px[(cy * size + cx) * 4 + 3]) * inv255
            if a > 0.68 { perimeterOpaque += 2 }
        }
        guard perimeterChecks > 0, Float(perimeterOpaque) / Float(perimeterChecks) >= 0.72 else {
            // Icône déjà en forme libre transparente : ne rien rogner ni gommer
            return nil
        }

        func medianCluster(cx: Int, cy: Int, span: Int) -> (r: Float, g: Float, b: Float)? {
            var list: [(r: Float, g: Float, b: Float)] = []
            list.reserveCapacity(25)
            let step = max(2, span / 2)
            for dy in stride(from: -span, through: span, by: step) {
                for dx in stride(from: -span, through: span, by: step) {
                    if let c = sampleRGB(x: cx + dx, y: cy + dy) {
                        list.append(c)
                    }
                }
            }
            guard list.count >= 3 else { return nil }
            let rs = list.map(\.r).sorted()
            let gs = list.map(\.g).sorted()
            let bs = list.map(\.b).sorted()
            let mid = list.count / 2
            return (rs[mid], gs[mid], bs[mid])
        }

        @inline(__always)
        func colorDist(_ a: (r: Float, g: Float, b: Float), _ b: (r: Float, g: Float, b: Float)) -> Float {
            let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
            let dl = 0.299 * dr + 0.587 * dg + 0.114 * db
            let c2 = (dr - dl) * (dr - dl) + (dg - dl) * (dg - dl) + (db - dl) * (db - dl)
            return sqrtf(dl * dl * 0.90 + c2 * 1.45)
        }

        let half = size / 2
        var tlCorner = medianCluster(cx: cornerInset, cy: cornerInset, span: cornerSpan)
        var trCorner = medianCluster(cx: size - 1 - cornerInset, cy: cornerInset, span: cornerSpan)
        var blCorner = medianCluster(cx: cornerInset, cy: size - 1 - cornerInset, span: cornerSpan)
        var brCorner = medianCluster(cx: size - 1 - cornerInset, cy: size - 1 - cornerInset, span: cornerSpan)

        let topMid = medianCluster(cx: half, cy: rimSampleInset, span: cornerSpan)
        let botMid = medianCluster(cx: half, cy: rimMax, span: cornerSpan)
        let leftMid = medianCluster(cx: rimSampleInset, cy: half, span: cornerSpan)
        let rightMid = medianCluster(cx: rimMax, cy: half, span: cornerSpan)

        // Si un élément du logo touche un coin, on corrige ce coin à partir des deux bords adjacents
        func cleanCorner(
            _ corner: (r: Float, g: Float, b: Float)?,
            adjA: (r: Float, g: Float, b: Float)?,
            adjB: (r: Float, g: Float, b: Float)?
        ) -> (r: Float, g: Float, b: Float)? {
            if let adjA, let adjB, colorDist(adjA, adjB) < 0.24 {
                let edgeAvg = ((adjA.r + adjB.r) * 0.5, (adjA.g + adjB.g) * 0.5, (adjA.b + adjB.b) * 0.5)
                if let c = corner, colorDist(c, edgeAvg) < 0.26 {
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
                maxCornerSpread = max(maxCornerSpread, colorDist(cornerVals[i], cornerVals[j]))
            }
        }

        let invSpan: Float = 1.0 / Float(max(1, rimMax - rimSampleInset))
        var uLUT = [Float](repeating: 0, count: size)
        for i in 0..<size {
            uLUT[i] = Float(max(rimSampleInset, min(rimMax, i)) - rimSampleInset) * invSpan
        }

        var ringSamples: [(x: Int, y: Int, r: Float, g: Float, b: Float)] = []
        ringSamples.reserveCapacity(140)
        let step = max(3, size / 64)
        let spanStart = cornerInset
        let spanEnd = size - 1 - cornerInset
        if spanEnd > spanStart {
            for t in stride(from: spanStart, through: spanEnd, by: step) {
                for (pxX, pxY) in [(t, rimSampleInset), (t, rimMax), (rimSampleInset, t), (rimMax, t)] {
                    if let c = sampleRGB(x: pxX, y: pxY) {
                        ringSamples.append((pxX, pxY, c.r, c.g, c.b))
                    }
                }
            }
        }

        @inline(__always)
        func bilinearBG(x: Int, y: Int) -> (r: Float, g: Float, b: Float) {
            let u = uLUT[x]
            let v = uLUT[y]
            let oneMinusU = 1.0 - u
            let oneMinusV = 1.0 - v
            let wTL = oneMinusU * oneMinusV
            let wTR = u * oneMinusV
            let wBL = oneMinusU * v
            let wBR = u * v
            return (
                tl.r * wTL + tr.r * wTR + bl.r * wBL + br.r * wBR,
                tl.g * wTL + tr.g * wTR + bl.g * wBL + br.g * wBR,
                tl.b * wTL + tr.b * wTR + bl.b * wBL + br.b * wBR
            )
        }

        var consistent = 0
        for s in ringSamples {
            if colorDist((s.r, s.g, s.b), bilinearBG(x: s.x, y: s.y)) < 0.20 {
                consistent += 1
            }
        }
        let ringMatchRatio = ringSamples.isEmpty ? 1.0 : Float(consistent) / Float(ringSamples.count)
        guard ringMatchRatio >= 0.45 else {
            // Icône pleine scène sans fond séparable (ex. Plans, Photos paysage) : préserver l'image entière
            return nil
        }

        // 2. Extraction RGB dé-prémultiplié et distance perceptuelle au champ de fond
        var rgb = [Float](repeating: 0.0, count: total * 3)
        var alphas = [Float](repeating: 0.0, count: total)
        var bgDist = [Float](repeating: 1.0, count: total)

        for y in 0..<size {
            let row = y * size
            let v = uLUT[y]
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
                let a = Float(px[off + 3]) * inv255
                alphas[idx] = a
                if a < 0.03 {
                    bgDist[idx] = 0.0
                    continue
                }
                let invA = 1.0 / (255.0 * a)
                let r = min(1.0, Float(px[off]) * invA)
                let g = min(1.0, Float(px[off + 1]) * invA)
                let b = min(1.0, Float(px[off + 2]) * invA)
                let rgbOff = idx * 3
                rgb[rgbOff] = r
                rgb[rgbOff + 1] = g
                rgb[rgbOff + 2] = b

                let u = uLUT[x]
                let oneMinusU = 1.0 - u
                let bgR = leftR * oneMinusU + rightR * u
                let bgG = leftG * oneMinusU + rightG * u
                let bgB = leftB * oneMinusU + rightB * u
                let dr = r - bgR, dg = g - bgG, db = b - bgB
                let dl = 0.299 * dr + 0.587 * dg + 0.114 * db
                let chromaSq = (dr - dl) * (dr - dl) + (dg - dl) * (dg - dl) + (db - dl) * (db - dl)
                bgDist[idx] = sqrtf(dl * dl * 0.90 + chromaSq * 1.45)
            }
        }

        // Luminance et saturation moyennes du fond pour adapter automatiquement la sensibilité :
        // - Sur fond sombre ou coloré (Terminal, Dictaphone, Raccourcis, Messages…) : tolérance plus large pour absorber les vignetages sombres en bas à droite.
        // - Sur fond gris clair ou blanc (Automator, Éditeur de script…) : critère strict afin de ne jamais entamer les objets blancs/argentés.
        let avgBGLum = (
            (0.2126 * tl.r + 0.7152 * tl.g + 0.0722 * tl.b)
            + (0.2126 * tr.r + 0.7152 * tr.g + 0.0722 * tr.b)
            + (0.2126 * bl.r + 0.7152 * bl.g + 0.0722 * bl.b)
            + (0.2126 * br.r + 0.7152 * br.g + 0.0722 * br.b)
        ) * 0.25
        let avgBGSat: Float = {
            var sum: Float = 0
            for c in cornerVals {
                let mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b))
                sum += mx > 0.001 ? ((mx - mn) / mx) : 0
            }
            return sum * 0.25
        }()
        let isBrightWhiteBG = (avgBGLum > 0.80 && avgBGSat < 0.10)
        let isPaleGrayBG = !isBrightWhiteBG && (avgBGLum > 0.66 && avgBGSat < 0.14)

        // Exécute le flood-fill avec un jeu de seuils paramétrable (permet un repli strict si trop d'avant-plan était mangé)
        func runFloodFill(directDist: Float, gradDistMax: Float, stepSqMax: Float) -> [Bool] {
            var visited = [Bool](repeating: false, count: total)
            var isBackground = [Bool](repeating: false, count: total)
            var queue = [Int32]()
            queue.reserveCapacity(total / 2)

            func trySeed(_ idx: Int) {
                guard !visited[idx] else { return }
                if alphas[idx] < 0.15 || bgDist[idx] < directDist {
                    visited[idx] = true
                    isBackground[idx] = true
                    queue.append(Int32(idx))
                }
            }

            let outerSeedInset = Int(Float(size) * 0.104)
            let outerSeedMax = size - 1 - outerSeedInset
            for i in 0..<size {
                trySeed(i)
                trySeed((size - 1) * size + i)
                trySeed(i * size)
                trySeed(i * size + (size - 1))
                if i >= rimSampleInset && i <= rimMax {
                    trySeed(rimSampleInset * size + i)
                    trySeed(rimMax * size + i)
                    trySeed(i * size + rimSampleInset)
                    trySeed(i * size + rimMax)
                }
                if i >= outerSeedInset && i <= outerSeedMax {
                    trySeed(outerSeedInset * size + i)
                    trySeed(outerSeedMax * size + i)
                    trySeed(i * size + outerSeedInset)
                    trySeed(i * size + outerSeedMax)
                }
            }

            var head = 0
            let maxIdx = size - 1
            let isPow2Size = (size & (size - 1)) == 0
            let sizeMask = size - 1
            let sizeShift = isPow2Size ? size.trailingZeroBitCount : 0
            let edgeBevelBandLow = Int(Float(size) * 0.088)
            let edgeBevelBandHigh = Int(Float(size) * 0.106)

            while head < queue.count {
                let cur = Int(queue[head])
                head += 1
                let cx = isPow2Size ? (cur & sizeMask) : (cur % size)
                let cy = isPow2Size ? (cur >> sizeShift) : (cur / size)
                let curAlpha = alphas[cur]
                let curRgbOff = cur * 3
                let cr = rgb[curRgbOff], cg = rgb[curRgbOff + 1], cb = rgb[curRgbOff + 2]

                @inline(__always)
                func visitNeighbor(_ nIdx: Int, nx: Int, ny: Int) {
                    guard !visited[nIdx] else { return }
                    let na = alphas[nIdx]
                    if na < 0.08 {
                        visited[nIdx] = true
                        isBackground[nIdx] = true
                        queue.append(Int32(nIdx))
                        return
                    }
                    let nd = bgDist[nIdx]
                    if nd < directDist {
                        visited[nIdx] = true
                        isBackground[nIdx] = true
                        queue.append(Int32(nIdx))
                        return
                    }
                    let onOuterCardBevel = (nx <= edgeBevelBandHigh && nx >= edgeBevelBandLow)
                        || (nx >= maxIdx - edgeBevelBandHigh && nx <= maxIdx - edgeBevelBandLow)
                        || (ny <= edgeBevelBandHigh && ny >= edgeBevelBandLow)
                        || (ny >= maxIdx - edgeBevelBandHigh && ny <= maxIdx - edgeBevelBandLow)
                    if onOuterCardBevel && curAlpha < 0.5 && nd < 0.34 {
                        visited[nIdx] = true
                        isBackground[nIdx] = true
                        queue.append(Int32(nIdx))
                        return
                    }
                    if curAlpha > 0.65 && nd < gradDistMax {
                        let nRgbOff = nIdx * 3
                        let nr = rgb[nRgbOff], ng = rgb[nRgbOff + 1], nb = rgb[nRgbOff + 2]
                        let dr = nr - cr, dg = ng - cg, db = nb - cb
                        if (dr * dr + dg * dg + db * db) < stepSqMax {
                            visited[nIdx] = true
                            isBackground[nIdx] = true
                            queue.append(Int32(nIdx))
                        }
                    }
                }

                if cx > 0 { visitNeighbor(cur - 1, nx: cx - 1, ny: cy) }
                if cx < maxIdx { visitNeighbor(cur + 1, nx: cx + 1, ny: cy) }
                if cy > 0 { visitNeighbor(cur - size, nx: cx, ny: cy - 1) }
                if cy < maxIdx { visitNeighbor(cur + size, nx: cx, ny: cy + 1) }
            }

            // Passe conservatrice pour les poches de fond fermées (engrenage Réglages, boucles B/A, cellules de grille Moniteur d'activité)
            if maxCornerSpread < 0.25 {
                var holeQueue = [Int32]()
                let interiorLo = rimSampleInset - 6
                let interiorHi = rimMax + 6
                let holeSeedDist: Float = (!isBrightWhiteBG && !isPaleGrayBG && avgBGLum < 0.32) ? 0.140 : 0.068
                let holeExpandDist: Float = (!isBrightWhiteBG && !isPaleGrayBG && avgBGLum < 0.32) ? 0.175 : 0.105
                let flatSqMax: Float = 0.016 * 0.016
                for y in stride(from: interiorLo, through: interiorHi, by: 2) {
                    let row = y * size
                    for x in stride(from: interiorLo, through: interiorHi, by: 2) {
                        let idx = row + x
                        guard !visited[idx], alphas[idx] > 0.85, bgDist[idx] < holeSeedDist else { continue }
                        let o = idx * 3
                        let r = rgb[o], g = rgb[o + 1], b = rgb[o + 2]
                        let ro = (idx + 1) * 3, bo = (idx + size) * 3
                        let d1 = (rgb[ro] - r) * (rgb[ro] - r) + (rgb[ro + 1] - g) * (rgb[ro + 1] - g) + (rgb[ro + 2] - b) * (rgb[ro + 2] - b)
                        let d2 = (rgb[bo] - r) * (rgb[bo] - r) + (rgb[bo + 1] - g) * (rgb[bo + 1] - g) + (rgb[bo + 2] - b) * (rgb[bo + 2] - b)
                        if d1 < flatSqMax && d2 < flatSqMax {
                            visited[idx] = true
                            isBackground[idx] = true
                            holeQueue.append(Int32(idx))
                        }
                    }
                }
                var hHead = 0
                let holeStepSq: Float = 0.020 * 0.020
                while hHead < holeQueue.count {
                    let cur = Int(holeQueue[hHead])
                    hHead += 1
                    let cx = isPow2Size ? (cur & sizeMask) : (cur % size)
                    let cy = isPow2Size ? (cur >> sizeShift) : (cur / size)
                    let curOff = cur * 3
                    let cr = rgb[curOff], cg = rgb[curOff + 1], cb = rgb[curOff + 2]

                    @inline(__always)
                    func visitHole(_ nIdx: Int) {
                        guard !visited[nIdx], alphas[nIdx] > 0.75, bgDist[nIdx] < holeExpandDist else { return }
                        let nOff = nIdx * 3
                        let dr = rgb[nOff] - cr, dg = rgb[nOff + 1] - cg, db = rgb[nOff + 2] - cb
                        if (dr * dr + dg * dg + db * db) < holeStepSq {
                            visited[nIdx] = true
                            isBackground[nIdx] = true
                            holeQueue.append(Int32(nIdx))
                        }
                    }
                    if cx > interiorLo { visitHole(cur - 1) }
                    if cx < interiorHi { visitHole(cur + 1) }
                    if cy > interiorLo { visitHole(cur - size) }
                    if cy < interiorHi { visitHole(cur + size) }
                }
            }
            return isBackground
        }

        // Mesure combien d'avant-plan survit dans la zone utile (16%..84%, inclut le > à gauche de Terminal)
        func centerForegroundRatio(_ bgMask: [Bool]) -> Float {
            let lo = Int(Float(size) * 0.16)
            let hi = Int(Float(size) * 0.84)
            var totalCenter = 0
            var fgCenter = 0
            for y in stride(from: lo, to: hi, by: 2) {
                let row = y * size
                for x in stride(from: lo, to: hi, by: 2) {
                    let idx = row + x
                    totalCenter += 1
                    if !bgMask[idx] && alphas[idx] > 0.40 {
                        fgCenter += 1
                    }
                }
            }
            return totalCenter > 0 ? Float(fgCenter) / Float(totalCenter) : 1.0
        }

        // Passe 1 adaptée à la luminosité du fond
        var isBackground: [Bool]
        if isBrightWhiteBG {
            isBackground = runFloodFill(directDist: 0.055, gradDistMax: 0.082, stepSqMax: 0.008 * 0.008)
            if centerForegroundRatio(isBackground) < 0.24 {
                return nil
            }
        } else if isPaleGrayBG {
            isBackground = runFloodFill(directDist: 0.135, gradDistMax: 0.215, stepSqMax: 0.016 * 0.016)
            if centerForegroundRatio(isBackground) < 0.055 {
                return nil
            }
        } else {
            let minFGThreshold: Float = avgBGLum < 0.42 ? 0.012 : 0.055
            isBackground = runFloodFill(directDist: 0.175, gradDistMax: 0.30, stepSqMax: 0.022 * 0.022)
            if centerForegroundRatio(isBackground) < minFGThreshold {
                let strictBg = runFloodFill(directDist: 0.085, gradDistMax: 0.14, stepSqMax: 0.012 * 0.012)
                if centerForegroundRatio(strictBg) >= minFGThreshold {
                    isBackground = strictBg
                } else {
                    return nil
                }
            }
        }

        // 4. Construction du matte haute précision :
        // Tout le fond détecté est effacé à 100% (1.0) — zéro résidu gris à 0.55 — et seule la frontière de 1–2 px reçoit un anti-crénelage doux.
        let maxIdx = size - 1
        var rawMatte = [Float](repeating: 0.0, count: total)
        var isBoundary = [Bool](repeating: false, count: total)

        for y in 0..<size {
            let row = y * size
            for x in 0..<size {
                let idx = row + x
                if isBackground[idx] {
                    if alphas[idx] < 0.08 {
                        rawMatte[idx] = 1.0
                        continue
                    }
                    let touchesFG = (x > 0 && !isBackground[idx - 1])
                        || (x < maxIdx && !isBackground[idx + 1])
                        || (y > 0 && !isBackground[idx - size])
                        || (y < maxIdx && !isBackground[idx + size])
                    if touchesFG {
                        isBoundary[idx] = true
                        let t = min(1.0, max(0.0, (bgDist[idx] - 0.04) / 0.16))
                        let smooth = t * t * (3.0 - 2.0 * t)
                        rawMatte[idx] = 1.0 - smooth * 0.35
                    } else {
                        rawMatte[idx] = 1.0
                    }
                } else {
                    let touchesBG = (x > 0 && isBackground[idx - 1])
                        || (x < maxIdx && isBackground[idx + 1])
                        || (y > 0 && isBackground[idx - size])
                        || (y < maxIdx && isBackground[idx + size])
                    if touchesBG {
                        isBoundary[idx] = true
                        if bgDist[idx] < 0.20 {
                            let t = max(0.0, 1.0 - bgDist[idx] / 0.20)
                            rawMatte[idx] = t * t * 0.42
                        }
                    }
                }
            }
        }

        // 5. Adoucissement sous-pixellique localisé UNIQUEMENT sur l'anneau frontière (n'altère jamais l'intérieur des icônes)
        var finalMatte = rawMatte
        for y in 1..<(size - 1) {
            let row = y * size
            for x in 1..<(size - 1) {
                let idx = row + x
                guard isBoundary[idx] else { continue }
                let sum = rawMatte[idx] * 4.0
                    + (rawMatte[idx - 1] + rawMatte[idx + 1] + rawMatte[idx - size] + rawMatte[idx + size]) * 2.0
                    + (rawMatte[idx - size - 1] + rawMatte[idx - size + 1] + rawMatte[idx + size - 1] + rawMatte[idx + size + 1])
                finalMatte[idx] = sum * (1.0 / 16.0)
            }
        }

        return SmoothMatteAnalysis(
            matte: finalMatte,
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
        tintRGB: (r: Double, g: Double, b: Double)
    ) -> Bool {
        let total = size * size
        let isGlassStyle = (style == .transparent || style == .clearLiquid || style == .clearDark || style == .frostedGlass)
        let needsMatte = isGlassStyle || style == .dark || style == .light
        let analysis = needsMatte ? analyzeBackgroundMatte(px: px, size: size) : nil
        let bgMatte = analysis?.matte ?? []

        let tintR = Float(tintRGB.r), tintG = Float(tintRGB.g), tintB = Float(tintRGB.b)
        let inv255: Float = 1.0 / 255.0
        let isPow2Size = (size & (size - 1)) == 0
        let sizeMask = size - 1
        let sizeShift = isPow2Size ? size.trailingZeroBitCount : 0
        let liftDarkInkOnGlass = (style == .transparent || style == .clearDark) && ((analysis?.avgBGLuminance ?? 0.0) > 0.70)

        for idx in 0..<total {
            let offset = idx * 4
            let a = Float(px[offset + 3]) * inv255
            guard a > 0.02 else { continue }

            let pxXInt = isPow2Size ? (idx & sizeMask) : (idx % size)
            let pxYInt = isPow2Size ? (idx >> sizeShift) : (idx / size)

            let invA = 1.0 / (255.0 * a)
            var r = min(1.0, Float(px[offset]) * invA)
            var g = min(1.0, Float(px[offset + 1]) * invA)
            var b = min(1.0, Float(px[offset + 2]) * invA)
            var outA = a

            let bgW = bgMatte.isEmpty ? 0.0 : bgMatte[idx]

            // Décontamination colorimétrique des pixels de bordure semi-transparents :
            // retire l'aura colorée héritée de l'ancien fond le long du contour détouré
            if isGlassStyle, bgW > 0.04, bgW < 0.95, let analysis {
                let fgAlpha = max(0.22, 1.0 - bgW)
                let u = analysis.uLUT[pxXInt]
                let v = analysis.uLUT[pxYInt]
                let oneMinusU = 1.0 - u
                let oneMinusV = 1.0 - v
                let wTL = oneMinusU * oneMinusV
                let wTR = u * oneMinusV
                let wBL = oneMinusU * v
                let wBR = u * v
                let corners = analysis.bilinearCorners
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

            case .light:
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

            case .tinted:
                let baseDarkR: Float = 0.04, baseDarkG: Float = 0.06, baseDarkB: Float = 0.10
                let curve = powf(max(0.0, lum), 0.88)
                r = baseDarkR + (tintR - baseDarkR) * curve
                g = baseDarkG + (tintG - baseDarkG) * curve
                b = baseDarkB + (tintB - baseDarkB) * curve

            case .monochrome:
                let contrasted = min(1.0, max(0.0, (lum - 0.5) * 1.16 + 0.52))
                r = contrasted * 0.96
                g = contrasted * 0.97
                b = contrasted

            case .transparent, .clearLiquid, .clearDark, .frostedGlass:
                if bgW > 0.005 {
                    outA *= (1.0 - bgW)
                }
                if liftDarkInkOnGlass && outA > 0.05 && lum < 0.26 && sat < 0.16 {
                    let inkT = (1.0 - min(1.0, lum / 0.26)) * (1.0 - min(1.0, sat / 0.16))
                    let targetW: Float = 0.88 - lum * 0.30
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
            px[offset]     = UInt8(clamping: Int((r * outA255).rounded()))
            px[offset + 1] = UInt8(clamping: Int((g * outA255).rounded()))
            px[offset + 2] = UInt8(clamping: Int((b * outA255).rounded()))
            px[offset + 3] = UInt8(clamping: Int(outA255.rounded()))
        }
        return analysis?.isSquircleCard == true
    }

    /// Rend chaque icône en parallèle multi-cœur en arrière-plan à 512×512 pour un démarrage et un changement de style fluides
    static func render(
        _ paths: [String],
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double) = (0.08, 0.54, 0.98)
    ) -> [String: CGImage] {
        guard !paths.isEmpty else { return [:] }
        var output: [String: CGImage] = [:]
        output.reserveCapacity(paths.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: paths.count) { index in
            let path = paths[index]
            autoreleasepool {
                if let cg = renderStyledHighResIcon(for: path, style: style, tintRGB: tintRGB) {
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

enum AppleAppLocalizer {
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

        // 1. Lecture directe depuis <App>.app/Contents/Resources/<lang>.lproj/InfoPlist.strings
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

        // 2. Dictionnaire intégré pour garantir le français même sur les bundles système scellés
        if lang == "fr" {
            if let bid = app.normalizedBundleID, let mapped = frNames[bid] {
                return mapped
            }
            if let mapped = frByEnglishName[app.normalizedName] {
                return mapped
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
