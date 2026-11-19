import Combine
import AppKit
import SwiftUI
import CoreImage

// MARK: - Fond d'écran flouté (comme le « Blur Wallpaper » de LaunchOS)

@MainActor
final class WallpaperProvider: ObservableObject {
    @Published private(set) var image: NSImage?
    private var currentKey: String?
    private var task: Task<Void, Never>?
    private weak var lastScreen: NSScreen?

    /// Recalcule l'image (ex. le style de fond a changé alors que le Launchpad est ouvert).
    func refresh() {
        if let screen = lastScreen ?? NSScreen.main { update(for: screen) }
    }

    func update(for screen: NSScreen) {
        lastScreen = screen
        let style = Prefs.backgroundStyle
        guard style.usesWallpaper else { return }
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { clear(); return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { clear(); return }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = screen.frame.size
        let sigma: Double = 60
        let key = "\(url.path)|\(modified)|\(Int(size.width))x\(Int(size.height))|\(sigma)"
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()
        task = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) { WallpaperBlur.render(url: url, targetSize: size, sigma: sigma) }.value
            guard let self, !Task.isCancelled else { return }
            self.image = rendered.map { NSImage(cgImage: $0, size: size) }
        }
    }

    private func clear() {
        currentKey = nil
        image = nil
    }
}

nonisolated enum WallpaperBlur {
    private static let sharedCIContext = CIContext(options: [.cacheIntermediates: false])

    static func render(url: URL, targetSize: CGSize, sigma: Double = 30) -> CGImage? {
        guard let input = CIImage(contentsOf: url), input.extent.width > 0, input.extent.height > 0 else { return nil }
        // Rendu à demi-résolution quand on floute : le flou masque les détails et c'est bien plus rapide.
        let fill = max(targetSize.width / input.extent.width, targetSize.height / input.extent.height)
        let scale = min(1, fill * (sigma > 0 ? 0.5 : 2))
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let output = sigma > 0
            ? scaled.clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.2, kCIInputBrightnessKey: -0.03])
            : scaled
        // Recadrage centré au ratio de l'écran (ex. fond 4096×2160 sur un écran 1710×1112).
        let extent = scaled.extent
        let screenRatio = targetSize.width / max(targetSize.height, 1)
        var crop = extent
        if extent.width / extent.height > screenRatio {
            crop.size.width = extent.height * screenRatio
            crop.origin.x = extent.midX - crop.width / 2
        } else {
            crop.size.height = extent.width / screenRatio
            crop.origin.y = extent.midY - crop.height / 2
        }
        return sharedCIContext.createCGImage(output, from: crop.integral)
    }
}

// MARK: - Verre (flou en direct de ce qui est derrière la fenêtre)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if view.material != material {
            view.material = material
        }
    }
}

// MARK: - Arrière-plan Liquid Glass (Inspiré du style Apple)

struct LiquidGlassBackground: View, Equatable {
    var intensity: Double = 0.85
    var backdropOpacity: Double = 0.40
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func == (lhs: LiquidGlassBackground, rhs: LiquidGlassBackground) -> Bool {
        lhs.intensity == rhs.intensity && lhs.backdropOpacity == rhs.backdropOpacity
    }

    var body: some View {
        let i = max(0.05, min(1.0, intensity))
        let clamped = max(0.0, min(1.0, backdropOpacity))
        let baseScale = clamped < 0.40 ? (clamped / 0.40) : 1.0
        ZStack {
            // 1. Flou d'arrière-plan en temps réel : diminue vers 0 quand l'opacité baisse
            VisualEffectBackground(material: .fullScreenUI)
                .opacity((reduceTransparency ? 1.0 : (0.25 + 0.75 * i)) * baseScale)

            // 2. Base semi-translucide constante sans voile blanc en haut
            Color.black.opacity((reduceTransparency ? 0.80 : 0.28) * baseScale)

            // 3. Nuance optique Liquid Glass discrète (sans reflet blanc supérieur)
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(red: 0.55, green: 0.45, blue: 0.95).opacity(0.045 * baseScale),
                    Color(red: 0.25, green: 0.65, blue: 1.0).opacity(0.04 * baseScale),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct LaunchpadBackground: View, Equatable {
    let wallpaper: WallpaperProvider
    let style: BackgroundStyle
    let dimming: Double
    var liquidGlassIntensity: Double = 0.85
    var backdropOpacity: Double = 0.40

    static func == (lhs: LaunchpadBackground, rhs: LaunchpadBackground) -> Bool {
        lhs.style == rhs.style
            && lhs.dimming == rhs.dimming
            && lhs.liquidGlassIntensity == rhs.liquidGlassIntensity
            && lhs.backdropOpacity == rhs.backdropOpacity
    }

    var body: some View {
        let clamped = max(0.0, min(1.0, backdropOpacity))
        let baseScale = clamped < 0.40 ? (clamped / 0.40) : 1.0
        let extraDark = clamped > 0.40 ? ((clamped - 0.40) / 0.60) : 0.0
        let scaledDimming = dimming * baseScale

        Color.clear
            .overlay {
                switch style {
                case .dark:
                    ZStack {
                        VisualEffectBackground(material: .fullScreenUI)
                            .opacity(baseScale)
                        Color.black.opacity(0.65 * baseScale)
                    }
                case .light:
                    ZStack {
                        VisualEffectBackground(material: .underWindowBackground)
                            .opacity(baseScale)
                        Color.white.opacity(0.32 * baseScale)
                    }
                case .liquidGlass:
                    LiquidGlassBackground(intensity: liquidGlassIntensity, backdropOpacity: clamped)
                }
            }
            .overlay {
                if scaledDimming > 0.001 {
                    Color.black.opacity(scaledDimming)
                }
            }
            .overlay {
                // Au-dessus de la valeur par défaut (40 %), augmente uniquement l'opacité sombre sans aucun voile blanc
                if extraDark > 0.001 {
                    Color.black.opacity(extraDark)
                }
            }
            .ignoresSafeArea()
    }
}
