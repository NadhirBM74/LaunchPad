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
                blur: fSize * 0.030,
                color: CGColor(gray: 0, alpha: 0.24)
            )
            finalCtx.addPath(bodyPath)
            let baseFill: CGColor
            switch style {
            case .transparent:
                baseFill = CGColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 0.14)
            case .clearLiquid:
                baseFill = CGColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 0.22)
            case .clearDark:
                baseFill = CGColor(red: 0.09, green: 0.11, blue: 0.22, alpha: 0.62)
            case .frostedGlass:
                baseFill = CGColor(red: 0.88, green: 0.90, blue: 0.98, alpha: 0.56)
            default:
                baseFill = CGColor(red: 1, green: 1, blue: 1, alpha: 0.18)
            }
            finalCtx.setFillColor(baseFill)
            finalCtx.fillPath()
            finalCtx.restoreGState()

            // Clip au squircle et dessin du contenu
            finalCtx.saveGState()
            finalCtx.addPath(bodyPath)
            finalCtx.clip()

            // Reflet diagonal subtil sur verre
            let sheenColors = [
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.12 : 0.26),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.02),
                CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.06 : 0.14)
            ] as CFArray
            if let sheenGrad = CGGradient(colorsSpace: cs, colors: sheenColors, locations: [0.0, 0.5, 1.0]) {
                finalCtx.drawLinearGradient(
                    sheenGrad,
                    start: CGPoint(x: targetBodyRect.minX, y: targetBodyRect.maxY),
                    end: CGPoint(x: targetBodyRect.maxX, y: targetBodyRect.minY),
                    options: []
                )
            }

            finalCtx.draw(styledCG, in: CGRect(x: 0, y: 0, width: fSize, height: fSize))

            // Bordure spéculaire en verre nette (sans bruit ni pixels crénelés)
            finalCtx.setLineWidth(max(2.0, fSize * 0.008))
            finalCtx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: style == .clearDark ? 0.28 : 0.52))
            finalCtx.addPath(bodyPath)
            finalCtx.strokePath()
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
    /// en échantillonnant le pourtour intérieur du squircle et en propageant de façon douce (zéro pixelisation).
    private static func computeSmoothBackgroundMatte(px: [UInt8], size: Int) -> [Double] {
        let total = size * size
        // 1. Échantillonnage des couleurs le long du bord intérieur du squircle (~13% depuis les bords)
        let ringMargin = Int(Double(size) * 0.14)
        let maxRing = size - 1 - ringMargin
        var samples: [(r: Double, g: Double, b: Double)] = []
        let step = max(4, size / 48)

        for t in stride(from: ringMargin, through: maxRing, by: step) {
            for (x, y) in [(t, ringMargin), (t, maxRing), (ringMargin, t), (maxRing, t)] {
                let off = (y * size + x) * 4
                let a = Double(px[off + 3]) / 255.0
                if a > 0.65 {
                    samples.append((
                        min(1.0, Double(px[off]) / (255.0 * a)),
                        min(1.0, Double(px[off + 1]) / (255.0 * a)),
                        min(1.0, Double(px[off + 2]) / (255.0 * a))
                    ))
                }
            }
        }

        // Si on n'a pas assez d'échantillons (icône non-squircle ou déjà détourée), retourner 0
        guard samples.count >= 8 else {
            return [Double](repeating: 0.0, count: total)
        }

        // Calcul de la couleur médiane/moyenne du bord + 2e cluster (haut vs bas pour les dégradés verticaux)
        let topSamples = samples.prefix(samples.count / 2)
        let botSamples = samples.suffix(samples.count / 2)

        func avgColor<S: Sequence>(_ seq: S) -> (r: Double, g: Double, b: Double) where S.Element == (r: Double, g: Double, b: Double) {
            var sr = 0.0, sg = 0.0, sb = 0.0, c = 0.0
            for s in seq { sr += s.r; sg += s.g; sb += s.b; c += 1.0 }
            return c > 0 ? (sr / c, sg / c, sb / c) : (0, 0, 0)
        }

        let topAvg = avgColor(topSamples)
        let botAvg = avgColor(botSamples)
        let globalAvg = avgColor(samples)

        // Vérifier que les bords sont raisonnablement cohérents (pas une photo complexe)
        var consistentCount = 0
        for s in samples {
            let dTop = hypot(s.r - topAvg.r, hypot(s.g - topAvg.g, s.b - topAvg.b))
            let dBot = hypot(s.r - botAvg.r, hypot(s.g - botAvg.g, s.b - botAvg.b))
            if min(dTop, dBot) < 0.28 { consistentCount += 1 }
        }
        guard Double(consistentCount) / Double(samples.count) > 0.55 else {
            return [Double](repeating: 0.0, count: total)
        }

        // 2. Distance couleur douce par rapport au dégradé de fond estimé
        var rawMatte = [Double](repeating: 0.0, count: total)
        let innerLow = 0.06
        let innerHigh = 0.22

        for y in 0..<size {
            let vy = Double(y) / Double(max(1, size - 1))
            let interpR = topAvg.r * (1.0 - vy) + botAvg.r * vy
            let interpG = topAvg.g * (1.0 - vy) + botAvg.g * vy
            let interpB = topAvg.b * (1.0 - vy) + botAvg.b * vy
            let rowOffset = y * size

            for x in 0..<size {
                let idx = rowOffset + x
                let off = idx * 4
                let a = Double(px[off + 3]) / 255.0
                if a < 0.03 {
                    rawMatte[idx] = 1.0
                    continue
                }
                let r = min(1.0, Double(px[off]) / (255.0 * a))
                let g = min(1.0, Double(px[off + 1]) / (255.0 * a))
                let b = min(1.0, Double(px[off + 2]) / (255.0 * a))

                let dInterp = hypot(r - interpR, hypot(g - interpG, b - interpB))
                let dGlobal = hypot(r - globalAvg.r, hypot(g - globalAvg.g, b - globalAvg.b))
                let dist = min(dInterp, dGlobal)

                // Smoothstep inversé : 1.0 si proche du fond, 0.0 si différent (logo)
                let t = min(1.0, max(0.0, (dist - innerLow) / (innerHigh - innerLow)))
                let smooth = t * t * (3.0 - 2.0 * t)
                rawMatte[idx] = 1.0 - smooth
            }
        }

        // 3. Lissage séparable 3×3 léger sur le matte pour éliminer tout grain/bavure sur les contours
        var temp = rawMatte
        for y in 1..<(size - 1) {
            let row = y * size
            for x in 1..<(size - 1) {
                let idx = row + x
                temp[idx] = (rawMatte[idx - 1] + 2.0 * rawMatte[idx] + rawMatte[idx + 1]) * 0.25
            }
        }
        var smoothed = temp
        for y in 1..<(size - 1) {
            let row = y * size
            for x in 1..<(size - 1) {
                let idx = row + x
                smoothed[idx] = (temp[idx - size] + 2.0 * temp[idx] + temp[idx + size]) * 0.25
            }
        }
        return smoothed
    }

    /// Shader 512×512 ultra-rapide et lissé adaptant chaque icône sans bavures ni pixels crénelés
    private static func applyPixelStyleShader(
        _ px: inout [UInt8],
        size: Int,
        style: IconAppearanceStyle,
        tintRGB: (r: Double, g: Double, b: Double)
    ) {
        let total = size * size
        let needsMatte = (style == .transparent || style == .clearLiquid || style == .clearDark || style == .frostedGlass || style == .dark || style == .light)
        let bgMatte = needsMatte ? computeSmoothBackgroundMatte(px: px, size: size) : []

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
            let bgW = bgMatte.isEmpty ? 0.0 : bgMatte[idx]

            switch style {
            case .dark:
                // Convertit en douceur les fonds clairs en obsidienne sombre (#16171E)
                let lumT = min(1.0, max(0.0, (lum - 0.56) / 0.30))
                let satT = 1.0 - min(1.0, max(0.0, (sat - 0.06) / 0.22))
                let t = max(bgW * lumT, lumT * satT)
                if t > 0.001 {
                    let darkR = 0.09 + (1.0 - lum) * 0.12
                    let darkG = 0.095 + (1.0 - lum) * 0.12
                    let darkB = 0.125 + (1.0 - lum) * 0.14
                    r = r * (1.0 - t) + darkR * t
                    g = g * (1.0 - t) + darkG * t
                    b = b * (1.0 - t) + darkB * t
                }

            case .light:
                // Éclaircit en douceur les fonds très sombres vers une surface nacrée claire
                let lumT = min(1.0, max(0.0, (0.28 - lum) / 0.24))
                let satT = 1.0 - min(1.0, max(0.0, (sat - 0.06) / 0.22))
                let t = max(bgW * lumT, lumT * satT)
                if t > 0.001 {
                    let lightVal = 0.94 - lum * 0.22
                    r = r * (1.0 - t) + lightVal * t
                    g = g * (1.0 - t) + lightVal * t
                    b = b * (1.0 - t) + (lightVal + 0.02) * t
                }

            case .tinted:
                let baseDarkR = 0.04, baseDarkG = 0.06, baseDarkB = 0.10
                let curve = pow(lum, 0.88)
                r = baseDarkR + (tintRGB.r - baseDarkR) * curve
                g = baseDarkG + (tintRGB.g - baseDarkG) * curve
                b = baseDarkB + (tintRGB.b - baseDarkB) * curve

            case .monochrome:
                let contrasted = min(1.0, max(0.0, (lum - 0.5) * 1.16 + 0.52))
                r = contrasted * 0.96
                g = contrasted * 0.97
                b = contrasted * 1.00

            case .transparent, .clearLiquid, .clearDark, .frostedGlass:
                // Grâce au masque lissé bgW, le fond du squircle s'efface proprement pour laisser
                // apparaître le socle de verre translucide dessiné en étape 3 — sans aucun grain ni bavure !
                if bgW > 0.01 {
                    let fgWeight = 1.0 - bgW
                    outA = a * fgWeight
                }
                if style == .frostedGlass || style == .clearLiquid {
                    // Légère brillance sur le premier plan pour s'harmoniser avec le verre
                    r = min(1.0, r * 0.95 + 0.05)
                    g = min(1.0, g * 0.95 + 0.05)
                    b = min(1.0, b * 0.96 + 0.06)
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

    static func localizedName(for app: AppInfo, languageCode: String) -> String {
        let lang = languageCode.lowercased()
        let isAppleApp = (app.bundleID?.lowercased().hasPrefix("com.apple.") == true)
            || app.id.hasPrefix("/System/Applications")
        guard isAppleApp else { return app.name }

        // 1. Lecture directe depuis <App>.app/Contents/Resources/<lang>.lproj/InfoPlist.strings
        let lprojCandidates = [lang, "\(lang)_FR", "\(lang)_ES", "\(lang)_DE", "\(lang)_IT", "\(lang)_PT", "French"]
        let resourcesDir = app.url.appendingPathComponent("Contents/Resources", isDirectory: true)
        for code in lprojCandidates {
            if code == "French" && lang != "fr" { continue }
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
