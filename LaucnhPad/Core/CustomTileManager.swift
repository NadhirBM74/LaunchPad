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
    }

    private func saveTiles() {
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
            let sanitized = tile.target.contains("://") ? tile.target : "https://\(tile.target)"
            url = URL(string: sanitized) ?? URL(fileURLWithPath: "/")
        } else {
            let encoded = tile.target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tile.target
            url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") ?? URL(fileURLWithPath: "/")
        }

        return AppInfo(
            id: tile.id,
            url: url,
            resolvedPath: tile.id,
            name: tile.title,
            bundleID: tile.kind == .web ? "com.apple.Safari" : "com.apple.shortcuts",
            category: "public.app-category.productivity",
            dateAdded: Date(),
            lastUsed: nil
        )
    }
}

// MARK: - Rendu graphique des tuiles personnalisées

nonisolated enum CustomTileRenderer {
    static let defaultWebColors = ["#0A84FF", "#30D158", "#BF5AF2", "#FF9F0A", "#FF375F", "#64D2FF"]
    static let defaultShortcutColors = ["#5E5CE6", "#BF5AF2", "#FF453A", "#FF9F0A", "#30D158", "#63E6E2"]

    static func icon(forID id: String, size: CGFloat = 256) -> NSImage {
        // En arrière-plan non-isolé, on lit le cache ou les données UserDefaults
        var symbol = "globe"
        var colorHex = "#0A84FF"

        if let data = UserDefaults.standard.data(forKey: PrefKey.customTiles),
           let tiles = try? JSONDecoder().decode([CustomTile].self, from: data),
           let tile = tiles.first(where: { $0.id == id }) {
            symbol = tile.symbol
            colorHex = tile.colorHex
        } else if id.hasPrefix("shortcut:") {
            symbol = "bolt.fill"
            colorHex = "#5E5CE6"
        }

        return renderImage(symbol: symbol, colorHex: colorHex, size: size)
    }

    static func renderImage(symbol: String, colorHex: String, size: CGFloat = 256) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let baseColor = NSColor(hexString: colorHex) ?? NSColor.systemBlue
        let rect = NSRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.19, yRadius: size * 0.19)

        // Fond dégradé subtil
        let topColor = baseColor.blended(withFraction: 0.18, of: .white) ?? baseColor
        let bottomColor = baseColor.blended(withFraction: 0.22, of: .black) ?? baseColor
        let gradient = NSGradient(starting: topColor, ending: bottomColor)
        gradient?.draw(in: path, angle: -45)

        // Liseré brillant supérieur
        let strokeColor = NSColor.white.withAlphaComponent(0.25)
        strokeColor.setStroke()
        path.lineWidth = size * 0.012
        path.stroke()

        // Symbole SF Symbol centré
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.40, weight: .semibold)
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
            // Dessin du symbole en blanc
            NSColor.white.set()
            configured.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        image.unlockFocus()
        return image
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
