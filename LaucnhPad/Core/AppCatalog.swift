import AppKit
import CoreServices

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
    var useOriginalColors: Bool { UserDefaults.standard.string(forKey: PrefKey.iconStyle) == "original" }

    func icon(for path: String) -> NSImage {
        if let image = images[path] { return image }
        let image = IconRenderer.sourceIcon(for: path, original: useOriginalColors)
        image.size = NSSize(width: 256, height: 256)
        images[path] = image
        return image
    }

    func contains(_ path: String) -> Bool { images[path] != nil }

    func store(_ rendered: [String: CGImage]) {
        for (path, cgImage) in rendered {
            images[path] = NSImage(cgImage: cgImage, size: NSSize(width: 256, height: 256))
        }
    }

    func invalidate(_ paths: [String]) { paths.forEach { images[$0] = nil } }
    func removeAll() { images.removeAll() }
}

nonisolated enum IconRenderer {
    static let pixelSize = 256

    /// Icône système (respecte le style Clair/Teinté de macOS, comme le Dock) ou icône d'origine en couleur (.icns du bundle).
    static func sourceIcon(for path: String, original: Bool) -> NSImage {
        if path.hasPrefix("web:") || path.hasPrefix("shortcut:") {
            return CustomTileRenderer.icon(forID: path)
        }
        if original, let image = bundleIcon(for: path) { return image }
        return NSWorkspace.shared.icon(forFile: path)
    }

    static func bundleIcon(for path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let info = AppScanner.infoDictionary(for: url)
        var candidates: [String] = []
        if let file = info?["CFBundleIconFile"] as? String, !file.isEmpty { candidates.append(file) }
        if let name = info?["CFBundleIconName"] as? String, !name.isEmpty { candidates.append(name) }
        candidates.append("AppIcon")
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        for candidate in candidates {
            let fileName = (candidate as NSString).pathExtension.isEmpty ? candidate + ".icns" : candidate
            let iconURL = resources.appendingPathComponent(fileName)
            let size = (try? FileManager.default.attributesOfItem(atPath: iconURL.path)[.size] as? Int) ?? 0
            // Certains .icns ne sont que des fichiers de quelques Ko sans image (ex. Livres) : on les ignore.
            if size > 10_000, let image = NSImage(contentsOf: iconURL), image.isValid, !image.representations.isEmpty {
                return image
            }
        }
        return nil
    }

    /// Rend chaque icône dans un bitmap pour éviter le coût du premier affichage sur le fil principal.
    static func render(_ paths: [String], original: Bool) -> [String: CGImage] {
        var output: [String: CGImage] = [:]
        for path in paths {
            autoreleasepool {
                var image = draw(sourceIcon(for: path, original: original))
                // Sécurité : une icône d'origine entièrement transparente est remplacée par l'icône système.
                if original, let rendered = image, isBlank(rendered) {
                    image = draw(NSWorkspace.shared.icon(forFile: path))
                }
                if let image { output[path] = image }
            }
        }
        return output
    }

    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    private static func draw(_ icon: NSImage) -> CGImage? {
        guard let colorSpace = sRGBColorSpace,
              let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        // Ombre portée intégrée à l'image (tient dans la marge transparente des icônes macOS).
        let size = CGFloat(pixelSize)
        context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.035,
                          color: CGColor(gray: 0, alpha: 0.32))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        let length = CFDataGetLength(data)
        // Échantillonne le canal alpha (RGBA) : un seul pixel visible suffit.
        var index = 3
        while index < length {
            if bytes[index] > 8 { return false }
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
