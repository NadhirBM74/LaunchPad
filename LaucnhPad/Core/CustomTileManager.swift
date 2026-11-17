import AppKit
import Foundation
import Combine

// MARK: - Modèle de tuile personnalisée (Signet Web ou Raccourci Apple)

nonisolated struct CustomTile: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case web
        case shortcut

        var title: String {
            switch self {
            case .web: return "Signet Web"
            case .shortcut: return "Raccourci Apple"
            }
        }
    }

    var id: String
    var title: String
    var target: String
    var kind: Kind
    var symbol: String
    var colorHex: String

    init(id: String = "", title: String, target: String, kind: Kind, symbol: String, colorHex: String) {
        let prefix = kind == .web ? "web:" : "shortcut:"
        self.id = id.isEmpty ? "\(prefix)\(UUID().uuidString)" : id
        self.title = title
        self.target = target
        self.kind = kind
        self.symbol = symbol
        self.colorHex = colorHex
    }
}

// MARK: - Gestionnaire des tuiles personnalisées

@MainActor
final class CustomTileManager: ObservableObject {
    static let shared = CustomTileManager()

    @Published private(set) var tiles: [CustomTile] = []

    private init() {
        loadTiles()
    }

    func loadTiles() {
        if let data = UserDefaults.standard.data(forKey: PrefKey.customTiles),
           let decoded = try? JSONDecoder().decode([CustomTile].self, from: data) {
            self.tiles = decoded
        } else {
            self.tiles = []
        }
        CustomTileRenderer.updateSnapshot(tiles)
    }

    private func saveTiles() {
        CustomTileRenderer.updateSnapshot(tiles)
        if let data = try? JSONEncoder().encode(tiles) {
            UserDefaults.standard.set(data, forKey: PrefKey.customTiles)
        }
    }

    @discardableResult
    func addTile(title: String, target: String, kind: CustomTile.Kind, symbol: String, colorHex: String) -> CustomTile {
        let newTile = CustomTile(title: title, target: target, kind: kind, symbol: symbol, colorHex: colorHex)
        tiles.append(newTile)
        saveTiles()
        return newTile
    }

    func removeTile(id: String) {
        tiles.removeAll { $0.id == id }
        saveTiles()
    }

    func tile(for id: String) -> CustomTile? {
        tiles.first { $0.id == id }
    }

    func asAppInfo(tile: CustomTile) -> AppInfo {
        let url: URL
        if tile.kind == .web {
            let trimmed = tile.target.trimmingCharacters(in: .whitespacesAndNewlines)
            let sanitized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
            url = URL(string: sanitized)
                ?? trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap { URL(string: $0.contains("://") ? $0 : "https://\($0)") }
                ?? URL(string: "about:blank")!
        } else {
            let encoded = tile.target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tile.target
            url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") ?? URL(string: "shortcuts://")!
        }

        return AppInfo(
            id: tile.id,
            url: url,
            resolvedPath: tile.id,
            name: tile.title,
            bundleID: tile.kind == .web ? "com.apple.Safari" : "com.apple.shortcuts",
            category: "public.app-category.productivity",
            dateAdded: nil,
            lastUsed: nil
        )
    }
}

// MARK: - Rendu graphique des tuiles personnalisées

nonisolated enum CustomTileRenderer {
    static let defaultWebColors = ["#0A84FF", "#30D158", "#BF5AF2", "#FF9F0A", "#FF375F", "#64D2FF"]
    static let defaultShortcutColors = ["#5E5CE6", "#BF5AF2", "#FF453A", "#FF9F0A", "#30D158", "#63E6E2"]

    private static let tilesLock = NSLock()
    nonisolated(unsafe) private static var snapshotByID: [String: CustomTile]? = nil
    nonisolated(unsafe) private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        return cache
    }()

    static func updateSnapshot(_ tiles: [CustomTile]) {
        var map: [String: CustomTile] = [:]
        map.reserveCapacity(tiles.count)
        for tile in tiles { map[tile.id] = tile }
        tilesLock.lock()
        snapshotByID = map
        tilesLock.unlock()
    }

    private static func cachedTile(forID id: String) -> CustomTile? {
        tilesLock.lock()
        if let existing = snapshotByID {
            let found = existing[id]
            tilesLock.unlock()
            return found
        }
        tilesLock.unlock()

        var loadedMap: [String: CustomTile] = [:]
        if let data = UserDefaults.standard.data(forKey: PrefKey.customTiles),
           let decoded = try? JSONDecoder().decode([CustomTile].self, from: data) {
            for tile in decoded { loadedMap[tile.id] = tile }
        }
        tilesLock.lock()
        if snapshotByID == nil {
            snapshotByID = loadedMap
        }
        let found = snapshotByID?[id]
        tilesLock.unlock()
        return found
    }

    static func icon(forID id: String, size: CGFloat = 256) -> NSImage {
        var symbol = "globe"
        var colorHex = "#0A84FF"

        if let tile = cachedTile(forID: id) {
            symbol = tile.symbol
            colorHex = tile.colorHex
        } else if id.hasPrefix("shortcut:") {
            symbol = "bolt.fill"
            colorHex = "#5E5CE6"
        }

        return renderImage(symbol: symbol, colorHex: colorHex, size: size)
    }

    static func renderImage(symbol: String, colorHex: String, size: CGFloat = 256) -> NSImage {
        let pxKey = "\(symbol)|\(colorHex)|\(Int(size.rounded()))" as NSString
        if let cached = imageCache.object(forKey: pxKey) {
            return cached
        }

        let pxDim = max(64, Int((size * 2.0).rounded()))
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: pxDim,
                  height: pxDim,
                  bitsPerComponent: 8,
                  bytesPerRow: pxDim * 4,
                  space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(pxDim) / size, y: CGFloat(pxDim) / size)

        let baseColor = (NSColor(hexString: colorHex) ?? NSColor.systemBlue).usingColorSpace(.sRGB) ?? NSColor.systemBlue
        let rect = CGRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
        let corner = size * 0.19
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // Fond dégradé subtil
        let topColor = (baseColor.blended(withFraction: 0.18, of: .white) ?? baseColor).cgColor
        let bottomColor = (baseColor.blended(withFraction: 0.22, of: .black) ?? baseColor).cgColor
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if let grad = CGGradient(colorsSpace: cs, colors: [topColor, bottomColor] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        // Liseré brillant supérieur
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
        ctx.setLineWidth(size * 0.012)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()

        // Symbole SF Symbol centré (rendu thread-safe sans lockFocus)
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.40, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let symbolImg = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)

        if let configured = symbolImg?.withSymbolConfiguration(config) {
            let symbolSize = configured.size
            let symbolRect = NSRect(
                x: (size - symbolSize.width) / 2,
                y: (size - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            configured.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
        }

        let resultImage: NSImage
        if let cg = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: size, height: size)
            let img = NSImage(size: NSSize(width: size, height: size))
            img.addRepresentation(rep)
            resultImage = img
        } else {
            resultImage = NSImage(size: NSSize(width: size, height: size))
        }
        imageCache.setObject(resultImage, forKey: pxKey)
        return resultImage
    }
}

// MARK: - Extension NSColor Hex

extension NSColor {
    nonisolated convenience init?(hexString: String) {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let rgbValue = UInt64(clean, radix: 16) else { return nil }

        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
