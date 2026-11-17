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
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.images.removeAll(keepingCapacity: false)
        }
        source.resume()
        self.memoryPressureSource = source
    }

    /// Style courant (lu une fois par accès : changer le réglage vide le cache).
    var useOriginalColors: Bool { currentAppearanceStyle != .system }

    var currentAppearanceStyle: IconAppearanceStyle {
        if UserDefaults.standard.bool(forKey: PrefKey.tintedIcons) {
            return .tinted
        }
        let raw = UserDefaults.standard.string(forKey: PrefKey.iconStyle) ?? "original"
        return IconAppearanceStyle(rawValue: raw) ?? .original
    }

    var activeTintColor: Color {
        let key = UserDefaults.standard.string(forKey: PrefKey.tintedIconColor) ?? "blue"
        switch key {
        case "graphite": return Color(white: 0.78)
        case "purple": return Color(red: 0.65, green: 0.42, blue: 1.0)
        case "orange": return Color(red: 1.0, green: 0.56, blue: 0.14)
        case "mint": return Color(red: 0.18, green: 0.85, blue: 0.68)
        case "rose": return Color(red: 1.0, green: 0.32, blue: 0.56)
        case "gold": return Color(red: 0.98, green: 0.78, blue: 0.22)
        default: return Color(red: 0.08, green: 0.54, blue: 0.98)
        }
    }

    func icon(for path: String) -> NSImage {
        // Vérification du cache avec contrôle qualité : on rejette toute icône en cache de moins de 512 px
        if let cached = images[path] {
            let maxPx = cached.representations.map(\.pixelsWide).max() ?? 0
            if maxPx >= IconRenderer.pixelSize {
                return cached
            }
        }

        let style = currentAppearanceStyle
        if !path.hasPrefix("web:") && !path.hasPrefix("shortcut:") {
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
                return customImg
            }
        }

        // Fallback pour signets web et raccourcis à 512×512 Retina
        if let cg = IconRenderer.renderStyledHighResIcon(for: path, style: style, tintRGB: (0.08, 0.54, 0.98)) {
            let hdImage = CustomAppIconRenderer.wrapCGImageAsRetinaNSImage(cg)
            images[path] = hdImage
            return hdImage
        }

        let fallback = IconRenderer.sourceIcon(for: path, original: useOriginalColors)
        fallback.size = NSSize(width: 256, height: 256)
        images[path] = fallback
        return fallback
    }

    func contains(_ path: String) -> Bool {
        guard let cached = images[path] else { return false }
        let maxPx = cached.representations.map(\.pixelsWide).max() ?? 0
        return maxPx >= IconRenderer.pixelSize
    }

    func store(_ rendered: [String: CGImage]) {
        let style = currentAppearanceStyle
        guard style == .system || style == .original else { return }
        for (path, cgImage) in rendered where images[path] == nil {
            if CustomIconManager.shared.hasOverride(for: path) { continue }
            images[path] = CustomAppIconRenderer.wrapCGImageAsRetinaNSImage(cgImage)
        }
    }

    func invalidate(_ paths: [String]) { paths.forEach { images[$0] = nil } }
    func removeAll() { images.removeAll() }
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
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? AppScanner.infoDictionary(for: url)

        var candidates: [String] = []
        if let name = info?["CFBundleIconName"] as? String, !name.isEmpty {
            candidates.append(name)
        }
        if let file = info?["CFBundleIconFile"] as? String, !file.isEmpty {
            if !candidates.contains(file) { candidates.append(file) }
            let stripped = (file as NSString).deletingPathExtension
            if !stripped.isEmpty && !candidates.contains(stripped) {
                candidates.append(stripped)
            }
        }
        if !candidates.contains("AppIcon") {
            candidates.append("AppIcon")
        }

        // 1. Lecture directe depuis Assets.car / Bundle resources (fournit 1024×1024 ou 512×512 en pleine couleur)
        if let bundle {
            for candidate in candidates {
                if let bImg = bundle.image(forResource: candidate), bImg.isValid, !bImg.representations.isEmpty {
                    let copy = (bImg.copy() as? NSImage) ?? bImg
                    copy.size = NSSize(width: pixelSize, height: pixelSize)
                    return copy
                }
            }
        }

        // 2. Lecture directe des fichiers .icns dans Contents/Resources/
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        for candidate in candidates {
            let fileName = (candidate as NSString).pathExtension.isEmpty ? candidate + ".icns" : candidate
            let iconURL = resources.appendingPathComponent(fileName)
            let size = (try? FileManager.default.attributesOfItem(atPath: iconURL.path)[.size] as? Int) ?? 0
            if size > 4_000, let image = NSImage(contentsOf: iconURL), image.isValid, !image.representations.isEmpty {
                image.size = NSSize(width: pixelSize, height: pixelSize)
                return image
            }
        }

        // 3. Recherche du plus grand fichier .icns dans Contents/Resources/ si le nom diffère
        if let files = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: [.fileSizeKey]) {
            let icnsFiles = files.filter { $0.pathExtension.lowercased() == "icns" }
            var bestImg: NSImage? = nil
            var bestPixels = 0
            for fileURL in icnsFiles {
                if let img = NSImage(contentsOf: fileURL) {
                    let maxP = img.representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
                    if maxP > bestPixels {
                        bestPixels = maxP
                        bestImg = img
                    }
                }
            }
            if let bestImg, bestPixels >= 128 * 128 {
                bestImg.size = NSSize(width: pixelSize, height: pixelSize)
                return bestImg
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

        // 2. Application du filtre de style pixel par pixel en 512×512 (sans jamais créer de double boîte !)
        if style != .original && style != .system && style != .classicApple {
            applyPixelStyleShader(&normPixels, size: size, style: style, tintRGB: tintRGB)
        }

        guard let styledCG = normCtx.makeImage() else { return sourceCG }

        // 3. Composition finale avec ombre portée macOS douce et bordure spéculaire optionnelle
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
        finalCtx.saveGState()
        finalCtx.setShadow(
            offset: CGSize(width: 0, height: -fSize * 0.012),
            blur: fSize * 0.034,
            color: CGColor(gray: 0, alpha: style == .light ? 0.22 : 0.32)
        )
        finalCtx.draw(styledCG, in: CGRect(x: 0, y: 0, width: fSize, height: fSize))
        finalCtx.restoreGState()

        return finalCtx.makeImage() ?? styledCG
    }

    /// Shader 512×512 ultra-rapide adaptant les surfaces des icônes tierces sans les réduire dans une boîte
    private static func applyPixelStyleShader(
        _ px: inout [UInt8],
        size: Int,
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double)
    ) {
        let total = size * size
        for idx in 0..<total {
            let offset = idx * 4
            let a = Double(px[offset + 3]) / 255.0
            guard a > 0.02 else { continue }

            // Dé-prémultiplication alpha
            var r = min(1.0, Double(px[offset]) / (255.0 * a))
            var g = min(1.0, Double(px[offset + 1]) / (255.0 * a))
            var b = min(1.0, Double(px[offset + 2]) / (255.0 * a))
            var outA = a

            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let delta = maxC - minC
            let sat = maxC > 0.001 ? (delta / maxC) : 0.0
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

            switch style {
            case .dark:
                // Convertit les fonds blancs/clairs neutres en obsidienne sombre (#16171E) tout en préservant à 100% les couleurs vives
                if sat < 0.22 && lum > 0.62 {
                    let t = min(1.0, max(0.0, (lum - 0.62) / 0.38)) * (1.0 - sat / 0.22)
                    let darkR = 0.09 + (1.0 - lum) * 0.14
                    let darkG = 0.095 + (1.0 - lum) * 0.14
                    let darkB = 0.12 + (1.0 - lum) * 0.16
                    r = r * (1.0 - t) + darkR * t
                    g = g * (1.0 - t) + darkG * t
                    b = b * (1.0 - t) + darkB * t
                }

            case .light:
                // Éclaircit les fonds noirs neutres vers une surface nacrée claire tout en gardant les éléments colorés intacts
                if sat < 0.20 && lum < 0.26 {
                    let t = min(1.0, max(0.0, (0.26 - lum) / 0.26)) * (1.0 - sat / 0.20)
                    let lightVal = 0.94 - lum * 0.25
                    r = r * (1.0 - t) + lightVal * t
                    g = g * (1.0 - t) + lightVal * t
                    b = b * (1.0 - t) + (lightVal + 0.02) * t
                }

            case .tinted:
                // Applique un dégradé teinté profond basé sur la luminance réelle de l'icône
                let baseDarkR = 0.04, baseDarkG = 0.06, baseDarkB = 0.10
                let curve = pow(lum, 0.88)
                r = baseDarkR + (tintRGB.r - baseDarkR) * curve
                g = baseDarkG + (tintRGB.g - baseDarkG) * curve
                b = baseDarkB + (tintRGB.b - baseDarkB) * curve

            case .monochrome:
                // Monochrome argenté/graphite à contraste renforcé
                let contrasted = min(1.0, max(0.0, (lum - 0.5) * 1.16 + 0.52))
                r = contrasted * 0.96
                g = contrasted * 0.97
                b = contrasted * 1.00

            case .transparent, .clearLiquid:
                // Rend les fonds neutres translucides façon verre liquide tout en gardant le logo central opaque
                if sat < 0.18 && (lum > 0.78 || lum < 0.18) {
                    outA = a * (style == .transparent ? 0.26 : 0.44)
                    r = r * 0.75 + 0.22
                    g = g * 0.76 + 0.24
                    b = b * 0.80 + 0.28
                }

            case .clearDark:
                if sat < 0.22 && lum > 0.65 {
                    outA = a * 0.78
                    r = 0.12
                    g = 0.14
                    b = 0.28
                }

            case .frostedGlass:
                if sat < 0.20 {
                    r = min(1.0, r * 0.85 + 0.14)
                    g = min(1.0, g * 0.86 + 0.15)
                    b = min(1.0, b * 0.90 + 0.18)
                }

            case .original, .classicApple, .system:
                break
            }

            // Re-prémultiplication alpha
            px[offset]     = UInt8(clamping: Int((r * outA * 255.0).rounded()))
            px[offset + 1] = UInt8(clamping: Int((g * outA * 255.0).rounded()))
            px[offset + 2] = UInt8(clamping: Int((b * outA * 255.0).rounded()))
            px[offset + 3] = UInt8(clamping: Int((outA * 255.0).rounded()))
        }
    }

    /// Rend chaque icône en arrière-plan à 512×512 pour un démarrage instantané
    static func render(_ paths: [String], original: Bool) -> [String: CGImage] {
        var output: [String: CGImage] = [:]
        let style: IconAppearanceStyle = original ? .original : .system
        for path in paths {
            autoreleasepool {
                if let cg = renderStyledHighResIcon(for: path, style: style, tintRGB: (0.08, 0.54, 0.98)) {
                    output[path] = cg
                }
            }
        }
        return output
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
