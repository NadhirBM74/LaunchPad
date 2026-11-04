import AppKit
import SwiftUI

/// Vue SwiftUI générant le fond Liquid Glass pour la fenêtre du DMG d'installation.
struct DMGBackgroundOpaque: View {
    let winWidth: CGFloat = 640
    let winHeight: CGFloat = 440

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Fond sombre solide 100% opaque (24-bit RGB)
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.17),
                    Color(red: 0.05, green: 0.06, blue: 0.11)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: winWidth, height: winHeight)

            // Grille de points subtils
            Canvas { context, size in
                let spacing: CGFloat = 28
                let dotSize: CGFloat = 1.6
                let cols = Int(size.width / spacing)
                let rows = Int(size.height / spacing)
                for col in 1..<cols {
                    for row in 1..<rows {
                        let rect = CGRect(
                            x: CGFloat(col) * spacing - dotSize/2,
                            y: CGFloat(row) * spacing - dotSize/2,
                            width: dotSize,
                            height: dotSize
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.045)))
                    }
                }
            }
            .frame(width: winWidth, height: winHeight)

            // Bordure extérieure arrondie subtile
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .padding(10)
                .frame(width: winWidth, height: winHeight)

            // Header (titre + badge PRO + sous-titre)
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    let fallbackIcon = NSImage(contentsOfFile: "/tmp/launchpad_transparent_icon.png")
                        ?? NSImage(contentsOfFile: "LaucnhPad/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png")
                        ?? NSImage(contentsOfFile: "../LaucnhPad/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png")

                    if let logoImg = fallbackIcon {
                        Image(nsImage: logoImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .shadow(color: Color.purple.opacity(0.35), radius: 4, y: 1)
                    }

                    Text("LaunchPad")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("PRO")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.55, green: 0.28, blue: 0.95), Color(red: 0.72, green: 0.38, blue: 0.98)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }

                Text("Votre nouveau Launchpad macOS en Liquid Glass")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .frame(width: winWidth)
            .position(x: winWidth / 2, y: 44)

            // Carte gauche (LaunchPad)
            glassCard
                .frame(width: 175, height: 175)
                .position(x: 175, y: 195)

            // Carte droite (Applications)
            glassCard
                .frame(width: 175, height: 175)
                .position(x: 465, y: 195)

            // Flèches centrales
            capsuleArrow
                .frame(width: 76, height: 36)
                .position(x: winWidth / 2, y: 190)

            // Pilule d'instruction remontée pour une visibilité immédiate sans scroll
            instructionPill
                .position(x: winWidth / 2, y: 340)
        }
        .frame(width: winWidth, height: winHeight)
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.06), Color.white.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 14, y: 6)
    }

    private var capsuleArrow: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.35))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.65))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.65, green: 0.45, blue: 0.98))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.05))
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        )
    }

    private var instructionPill: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.38, blue: 0.95), Color(red: 0.68, green: 0.45, blue: 0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 20, height: 20)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 4) {
                Text("Glissez")
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("LaunchPad")
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("dans le dossier")
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("Applications")
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .font(.system(size: 11.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.065))
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        )
    }
}

@main
struct GeneratorOpaque {
    @MainActor
    static func main() {
        let view = DMGBackgroundOpaque()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0 // @2x Retina

        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {

            let width = rep.pixelsWide
            let height = rep.pixelsHigh
            // Bitmap 24-bit RGB sans couche alpha pour que Finder affiche les étiquettes proprement
            let opaqueRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 3,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: width * 3,
                bitsPerPixel: 24
            )!
            opaqueRep.size = NSSize(width: 640, height: 440)

            for y in 0..<height {
                for x in 0..<width {
                    if let c = rep.colorAt(x: x, y: y) {
                        opaqueRep.setColor(NSColor(calibratedRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: 1.0), atX: x, y: y)
                    }
                }
            }

            if let pngData = opaqueRep.representation(using: .png, properties: [:]) {
                let outURL = URL(fileURLWithPath: "/tmp/launchpad_bg_opaque.png")
                try? pngData.write(to: outURL)
                print("Fond généré : /tmp/launchpad_bg_opaque.png (\(opaqueRep.pixelsWide)x\(opaqueRep.pixelsHigh))")
            }
        }
    }
}
