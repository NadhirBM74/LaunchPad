#!/bin/bash
set -e

# ==============================================================================
# Script de création du DMG professionnel LaunchPad pour macOS
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/Partage_LaunchPad"
ICON_ICNS="/tmp/launchpad_icon_build/LaunchPad.icns"
ICON_PNG="/tmp/launchpad_transparent_icon.png"
OUTPUT_DMG="$DIST_DIR/LaunchPad.dmg"
TEMP_DMG_SOURCE="/tmp/dmg_source"
BG_IMAGE="/tmp/launchpad_bg_opaque.png"

echo "🎨 1. Génération du fond Liquid Glass 24-bit Retina..."
swiftc -parse-as-library "$PROJECT_DIR/Scripts/generate_dmg_background.swift" -o /tmp/gen_dmg_bg
/tmp/gen_dmg_bg

echo "📦 2. Compilation de LaunchPad en mode Release..."
cd "$PROJECT_DIR"
xcodebuild -scheme LaunchPad -configuration Release -derivedDataPath /tmp/LaunchPad_DerivedData build -quiet

BUILT_APP="/tmp/LaunchPad_DerivedData/Build/Products/Release/LaunchPad.app"

# Fallback pour l'icône icns et png si pas dans /tmp
if [ ! -f "$ICON_ICNS" ] && [ -f "$BUILT_APP/Contents/Resources/AppIcon.icns" ]; then
    ICON_ICNS="$BUILT_APP/Contents/Resources/AppIcon.icns"
fi

if [ ! -f "$ICON_PNG" ] && [ -f "$PROJECT_DIR/LaucnhPad/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" ]; then
    ICON_PNG="$PROJECT_DIR/LaucnhPad/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
fi

echo "🧹 3. Préparation du dossier source DMG..."
rm -rf "$TEMP_DMG_SOURCE" && mkdir -p "$TEMP_DMG_SOURCE"
ditto "$BUILT_APP" "$TEMP_DMG_SOURCE/LaunchPad.app"

# Vérification de la signature
codesign --force --deep --sign - "$TEMP_DMG_SOURCE/LaunchPad.app"

echo "💿 4. Démontage des anciens volumes éventuels..."
hdiutil detach "/Volumes/LaunchPad" -force 2>/dev/null || true
hdiutil detach "/Volumes/LaunchPad 1" -force 2>/dev/null || true

echo "🔨 5. Création du fichier DMG avec create-dmg..."
mkdir -p "$DIST_DIR"
rm -f "$OUTPUT_DMG"

VOLICON_ARGS=()
if [ -f "$ICON_ICNS" ]; then
    VOLICON_ARGS=(--volicon "$ICON_ICNS")
fi

create-dmg \
  --volname "LaunchPad" \
  "${VOLICON_ARGS[@]}" \
  --background "$BG_IMAGE" \
  --window-pos 200 120 \
  --window-size 640 440 \
  --icon-size 96 \
  --text-size 13 \
  --icon "LaunchPad.app" 175 195 \
  --hide-extension "LaunchPad.app" \
  --app-drop-link 465 195 \
  --overwrite \
  "$OUTPUT_DMG" \
  "$TEMP_DMG_SOURCE"

echo "✨ 6. Application du logo personnalisé sur le fichier .dmg..."
swift - << EOF
import AppKit

let dmgPath = "$OUTPUT_DMG"
if let img = NSImage(contentsOfFile: "$ICON_PNG") {
    let success = NSWorkspace.shared.setIcon(img, forFile: dmgPath, options: [])
    print("Icône appliquée sur le DMG : \(success)")
}
EOF

echo "✅ DMG prêt : $OUTPUT_DMG"
