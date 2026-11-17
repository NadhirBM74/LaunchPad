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
        let standardCorner: CGFloat = standardBody * 0.225
        let targetBodyRect = CGRect(x: standardInset, y: standardInset, width: standardBody, height: standardBody)

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
            let clipPath = CGPath(
                roundedRect: targetBodyRect,
                cornerWidth: standardCorner,
                cornerHeight: standardCorner,
                transform: nil
            )
            normCtx.addPath(clipPath)
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

        // 2. Application du filtre de style pixel par pixel en 512×512 (avec matting doux sans bavures)
        if style != .original && style != .system && style != .classicApple {
            applyPixelStyleShader(&normPixels, size: size, style: style, tintRGB: tintRGB)
        }

        guard let styledCG = normCtx.makeImage() else { return sourceCG }

        // 3. Composition finale : socle verre translucide + bordure spéculaire + ombre douce
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
            // Pour les styles transparents/verre : on dessine d'abord une ombre douce sous le squircle,
            // puis le fond verre translucide uniforme, puis l'icône détourée par-dessus, puis le biseau lumineux.
            let bodyPath = CGPath(
                roundedRect: targetBodyRect,
                cornerWidth: standardCorner,
                cornerHeight: standardCorner,
                transform: nil
            )

            finalCtx.saveGState()
            finalCtx.setShadow(
                offset: CGSize(width: 0, height: -fSize * 0.012),
                blur: fSize * 0.032,
                color: CGColor(gray: 0, alpha: style == .transparent ? 0.18 : 0.24)
            )
            finalCtx.addPath(bodyPath)
            let baseFill: CGColor
            switch style {
            case .transparent:
                baseFill = CGColor(red: 0.94, green: 0.96, blue: 1.0, alpha: 0.09)
            case .clearLiquid:
                baseFill = CGColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 0.15)
            case .clearDark:
                baseFill = CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.50)
            case .frostedGlass:
                baseFill = CGColor(red: 0.90, green: 0.93, blue: 0.99, alpha: 0.34)
            default:
                baseFill = CGColor(red: 1, green: 1, blue: 1, alpha: 0.14)
            }
            finalCtx.setFillColor(baseFill)
            finalCtx.fillPath()
            finalCtx.restoreGState()

            // Clip au squircle et dessin du contenu
            finalCtx.saveGState()
            finalCtx.addPath(bodyPath)
            finalCtx.clip()

            // Reflet diagonal subtil en verre cristal sur l'icône
            let sheenColors = [
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.10 : 0.22),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.00),
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.05 : 0.11)
            ] as CFArray
            if let sheenGrad = CGGradient(colorsSpace: cs, colors: sheenColors, locations: [0.0, 0.48, 1.0]) {
                finalCtx.drawLinearGradient(
                    sheenGrad,
                    start: CGPoint(x: targetBodyRect.minX, y: targetBodyRect.maxY),
                    end: CGPoint(x: targetBodyRect.maxX, y: targetBodyRect.minY),
                    options: []
                )
            }

            finalCtx.draw(styledCG, in: CGRect(x: 0, y: 0, width: fSize, height: fSize))

            // Bordure spéculaire dégradée fine façon Liquid Glass d'Apple
            finalCtx.setLineWidth(max(1.8, fSize * 0.007))
            let rimColors = [
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.30 : 0.58),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.14),
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.22 : 0.38)
            ] as CFArray
            if let rimGrad = CGGradient(colorsSpace: cs, colors: rimColors, locations: [0.0, 0.5, 1.0]) {
                finalCtx.addPath(bodyPath)
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

    /// Calcule un masque de fond lissé (`0.0` = logo/premier plan, `1.0` = fond du squircle)
    /// par modélisation bilinéaire 4 coins + remplissage par propagation (flood-fill) depuis le pourtour.
    /// Détoure proprement les fonds unis, dégradés verticaux/diagonaux et cartes blanches (Messages, WhatsApp, Canopy, FaceTime, Discord…).
    private static func computeSmoothBackgroundMatte(px: [UInt8], size: Int) -> [Float] {
        let total = size * size
        // Périmètre intérieur sûr à 13.5% du canevas (~17 px à l'intérieur du bord squircle 9.1%)
        let m = Int(Float(size) * 0.135)
        let maxM = size - 1 - m
        let cornerInset = Int(Float(size) * 0.165)
        let cornerSpan = Int(Float(size) * 0.065)
        let step = max(3, size / 64)
        let inv255: Float = 1.0 / 255.0

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

        // Échantillonnage des 4 coins avec valeur médiane (résistant aux logos traversant un bord)
        func cornerCluster(cx: Int, cy: Int) -> (r: Float, g: Float, b: Float)? {
            var list: [(r: Float, g: Float, b: Float)] = []
            list.reserveCapacity(25)
            for dy in stride(from: -cornerSpan, through: cornerSpan, by: max(3, cornerSpan / 4)) {
                for dx in stride(from: -cornerSpan, through: cornerSpan, by: max(3, cornerSpan / 4)) {
                    if let c = sampleRGB(x: cx + dx, y: cy + dy) {
                        list.append(c)
                    }
                }
            }
            guard !list.isEmpty else { return nil }
            let rs = list.map(\.r).sorted()
            let gs = list.map(\.g).sorted()
            let bs = list.map(\.b).sorted()
            let mid = list.count / 2
            return (rs[mid], gs[mid], bs[mid])
        }

        var ringSamples: [(x: Int, y: Int, r: Float, g: Float, b: Float)] = []
        ringSamples.reserveCapacity(128)
        let spanStart = m + 16
        let spanEnd = maxM - 16
        if spanEnd > spanStart {
            for t in stride(from: spanStart, through: spanEnd, by: step) {
                for (pxX, pxY) in [(t, m), (t, maxM), (m, t), (maxM, t)] {
                    if let c = sampleRGB(x: pxX, y: pxY) {
                        ringSamples.append((pxX, pxY, c.r, c.g, c.b))
                    }
                }
            }
        }

        let tlCorner = cornerCluster(cx: cornerInset, cy: cornerInset)
        let trCorner = cornerCluster(cx: size - 1 - cornerInset, cy: cornerInset)
        let blCorner = cornerCluster(cx: cornerInset, cy: size - 1 - cornerInset)
        let brCorner = cornerCluster(cx: size - 1 - cornerInset, cy: size - 1 - cornerInset)

        let cornerList = [tlCorner, trCorner, blCorner, brCorner].compactMap { $0 }
        let ringCount = ringSamples.count + cornerList.count
        guard ringCount >= 8, !cornerList.isEmpty else {
            return []
        }

        let invCorners = 1.0 / Float(cornerList.count)
        let fallback = (
            r: cornerList.reduce(Float(0)) { $0 + $1.r } * invCorners,
            g: cornerList.reduce(Float(0)) { $0 + $1.g } * invCorners,
            b: cornerList.reduce(Float(0)) { $0 + $1.b } * invCorners
        )
        let tl = tlCorner ?? fallback
        let tr = trCorner ?? fallback
        let bl = blCorner ?? fallback
        let br = brCorner ?? fallback

        let invSpan: Float = 1.0 / Float(max(1, maxM - m))
        var uLUT = [Float](repeating: 0, count: size)
        for i in 0..<size {
            uLUT[i] = Float(max(m, min(maxM, i)) - m) * invSpan
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

        // Vérifier que les pixels de bord suivent un champ continu (dégradé / uni / bilinéaire)
        var consistent = 0
        for s in ringSamples {
            let bg = bilinearBG(x: s.x, y: s.y)
            let dr = s.r - bg.r, dg = s.g - bg.g, db = s.b - bg.b
            if (dr * dr + dg * dg + db * db) < 0.1156 { consistent += 1 }
        }
        let ringMatchRatio = ringSamples.isEmpty ? 1.0 : Float(consistent) / Float(ringSamples.count)
        guard ringMatchRatio > 0.42 else {
            return []
        }

        // 2. Extraction RGB dé-prémultiplié & distance locale au champ bilinéaire (tampons Float compacts)
        var rgb = [Float](repeating: 0.0, count: total * 3)
        var alphas = [Float](repeating: 0.0, count: total)
        var bgDist = [Float](repeating: 1.0, count: total)

        for y in 0..<size {
            let row = y * size
            let v = uLUT[y]
            let oneMinusV = 1.0 - v
            let topR = tl.r * oneMinusV + bl.r * v
            let topG = tl.g * oneMinusV + bl.g * v
            let topB = tl.b * oneMinusV + bl.b * v
            let botR = tr.r * oneMinusV + br.r * v
            let botG = tr.g * oneMinusV + br.g * v
            let botB = tr.b * oneMinusV + br.b * v

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
                let bgR = topR * oneMinusU + botR * u
                let bgG = topG * oneMinusU + botG * u
                let bgB = topB * oneMinusU + botB * u
                let dr = r - bgR, dg = g - bgG, db = b - bgB
                bgDist[idx] = sqrtf(dr * dr + dg * dg + db * db)
            }
        }

        // 3. Flood-fill connecté depuis le pourtour et les pixels transparents externes
        var visited = [Bool](repeating: false, count: total)
        var isBackground = [Bool](repeating: false, count: total)
        var queue = [Int32]()
        queue.reserveCapacity(total / 2)

        func trySeed(_ idx: Int) {
            guard !visited[idx] else { return }
            if alphas[idx] < 0.12 || bgDist[idx] < 0.25 {
                visited[idx] = true
                isBackground[idx] = true
                queue.append(Int32(idx))
            }
        }

        for i in 0..<size {
            trySeed(i)
            trySeed((size - 1) * size + i)
            trySeed(i * size)
            trySeed(i * size + (size - 1))
            if i >= m && i <= maxM {
                trySeed(m * size + i)
                trySeed(maxM * size + i)
                trySeed(i * size + m)
                trySeed(i * size + maxM)
            }
        }

        var head = 0
        let maxIdx = size - 1
        let stepDistSqMax: Float = 0.045 * 0.045
        let isPow2Size = (size & (size - 1)) == 0
        let sizeMask = size - 1
        let sizeShift = isPow2Size ? size.trailingZeroBitCount : 0

        while head < queue.count {
            let cur = Int(queue[head])
            head += 1
            let cx = isPow2Size ? (cur & sizeMask) : (cur % size)
            let cy = isPow2Size ? (cur >> sizeShift) : (cur / size)
            let curAlpha = alphas[cur]
            let curRgbOff = cur * 3
            let cr = rgb[curRgbOff], cg = rgb[curRgbOff + 1], cb = rgb[curRgbOff + 2]

            @inline(__always)
            func visitNeighbor(_ nIdx: Int) {
                guard !visited[nIdx] else { return }
                if alphas[nIdx] < 0.08 || bgDist[nIdx] < 0.24 {
                    visited[nIdx] = true
                    isBackground[nIdx] = true
                    queue.append(Int32(nIdx))
                    return
                }
                if curAlpha > 0.7 && bgDist[nIdx] < 0.36 {
                    let nRgbOff = nIdx * 3
                    let dr = rgb[nRgbOff] - cr
                    let dg = rgb[nRgbOff + 1] - cg
                    let db = rgb[nRgbOff + 2] - cb
                    if (dr * dr + dg * dg + db * db) < stepDistSqMax {
                        visited[nIdx] = true
                        isBackground[nIdx] = true
                        queue.append(Int32(nIdx))
                    }
                }
            }

            if cx > 0 { visitNeighbor(cur - 1) }
            if cx < maxIdx { visitNeighbor(cur + 1) }
            if cy > 0 { visitNeighbor(cur - size) }
            if cy < maxIdx { visitNeighbor(cur + size) }
        }

        // 4. Matte adouci sur la frontière logo/fond pour zéro crénelage
        var bufA = [Float](repeating: 0.0, count: total)
        let edgeInnerLow: Float = 0.06
        let invEdgeSpan: Float = 1.0 / (0.24 - 0.06)
        for idx in 0..<total where isBackground[idx] {
            if alphas[idx] < 0.08 {
                bufA[idx] = 1.0
            } else {
                let d = bgDist[idx]
                let t = min(1.0, max(0.0, (d - edgeInnerLow) * invEdgeSpan))
                bufA[idx] = 1.0 - (t * t * (3.0 - 2.0 * t)) * 0.45
            }
        }

        // 5. Lissage séparable 3×3 avec réutilisation de 2 tampons uniquement
        var bufB = bufA
        for y in 1..<(size - 1) {
            let row = y * size
            for x in 1..<(size - 1) {
                let idx = row + x
                bufB[idx] = (bufA[idx - 1] + 2.0 * bufA[idx] + bufA[idx + 1]) * 0.25
            }
        }
        bufA = bufB
        for y in 1..<(size - 1) {
            let row = y * size
            for x in 1..<(size - 1) {
                let idx = row + x
                bufA[idx] = (bufB[idx - size] + 2.0 * bufB[idx] + bufB[idx + size]) * 0.25
            }
        }
        return bufA
    }

    /// Shader 512×512 ultra-rapide et lissé adaptant chaque icône sans bavures ni pixels crénelés
    private static func applyPixelStyleShader(
        _ px: inout [UInt8],
        size: Int,
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double)
    ) {
        let total = size * size
        let isGlassStyle = (style == .transparent || style == .clearLiquid || style == .clearDark || style == .frostedGlass)
        let needsMatte = isGlassStyle || style == .dark || style == .light
        let bgMatte = needsMatte ? computeSmoothBackgroundMatte(px: px, size: size) : []
        // Rognage ultra-fin du liseré externe (1.8% à l'intérieur du squircle) lorsqu'un fond squircle a été détouré
        let clipOuterRimForGlass = isGlassStyle && !bgMatte.isEmpty && bgMatte.contains(where: { $0 > 0.5 })
        let innerTrimMargin = Float(size) * 0.130
        let innerTrimMax = Float(size) - 1.0 - innerTrimMargin
        let innerTrimW = innerTrimMax - innerTrimMargin
        let innerCorner = innerTrimW * 0.225
        let halfSize = Float(size) * 0.5
        let cornerThreshold = innerTrimW * 0.5 - innerCorner
        let tintR = Float(tintRGB.r), tintG = Float(tintRGB.g), tintB = Float(tintRGB.b)
        let inv255: Float = 1.0 / 255.0
        let isPow2Size = (size & (size - 1)) == 0
        let sizeMask = size - 1
        let sizeShift = isPow2Size ? size.trailingZeroBitCount : 0

        for idx in 0..<total {
            let offset = idx * 4
            let a = Float(px[offset + 3]) * inv255
            guard a > 0.02 else { continue }

            let invA = 1.0 / (255.0 * a)
            var r = min(1.0, Float(px[offset]) * invA)
            var g = min(1.0, Float(px[offset + 1]) * invA)
            var b = min(1.0, Float(px[offset + 2]) * invA)
            var outA = a

            if clipOuterRimForGlass {
                let pxX = Float(isPow2Size ? (idx & sizeMask) : (idx % size))
                let pxY = Float(isPow2Size ? (idx >> sizeShift) : (idx / size))
                if pxX < innerTrimMargin || pxX > innerTrimMax || pxY < innerTrimMargin || pxY > innerTrimMax {
                    outA = 0.0
                } else {
                    let cxEdge = abs(pxX - halfSize) - cornerThreshold
                    let cyEdge = abs(pxY - halfSize) - cornerThreshold
                    if cxEdge > 0 && cyEdge > 0 {
                        let cornerDist = sqrtf(cxEdge * cxEdge + cyEdge * cyEdge) - innerCorner
                        if cornerDist > 0.0 {
                            outA = 0.0
                        } else if cornerDist > -2.0 {
                            outA *= min(1.0, max(0.0, -cornerDist * 0.5))
                        }
                    }
                }
            }

            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let sat = maxC > 0.001 ? ((maxC - minC) / maxC) : 0.0
            let lum: Float = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let bgW = bgMatte.isEmpty ? 0.0 : bgMatte[idx]

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
                if bgW > 0.01 {
                    outA *= (1.0 - bgW)
                }
                if style == .frostedGlass || style == .clearLiquid {
                    r = min(1.0, r * 0.95 + 0.05)
                    g = min(1.0, g * 0.95 + 0.05)
                    b = min(1.0, b * 0.96 + 0.06)
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
    static func title(for key: String) -> String {
        switch key {
        case "business": "Économie et entreprise"
        case "developer-tools": "Outils de développement"
        case "education": "Éducation"
        case "entertainment": "Divertissement"
        case "finance": "Finance"
        case "games": "Jeux"
        case "graphics-design": "Graphisme et design"
        case "healthcare-fitness": "Santé et forme"
        case "lifestyle": "Style de vie"
        case "medical": "Médecine"
        case "music": "Musique"
        case "news": "Actualités"
        case "photography": "Photographie"
        case "productivity": "Productivité"
        case "reference": "Références"
        case "social-networking": "Réseaux sociaux"
        case "sports": "Sports"
        case "travel": "Voyages"
        case "utilities": "Utilitaires"
        case "video": "Vidéo"
        case "weather": "Météo"
        case "books": "Livres"
        case "kids": "Enfants"
        default: key.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
