import SwiftUI

// MARK: - Zone Principale d'affichage des Widgets Personnalisés

struct CustomWidgetsAreaView: View {
    @ObservedObject var vm: LaunchpadViewModel
    var windowWidth: CGFloat = 1440

    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var licenseManager = LicenseManager.shared

    @State private var draggedKind: WidgetKind?
    @State private var dragLocation: CGPoint = .zero
    @State private var grabOffset: CGPoint = .zero
    @State private var widgetFrames: [WidgetKind: CGRect] = [:]

    private var isEditing: Bool {
        (vm.editing || vm.optionHeld) && !vm.isSearching
    }

    private var enabledWidgets: [CustomWidgetConfig] {
        widgetManager.widgets.filter { $0.isEnabled }.sorted { $0.order < $1.order }
    }

    var body: some View {
        if licenseManager.isPro && !enabledWidgets.isEmpty {
            ZStack(alignment: .topLeading) {
                Group {
                    switch widgetManager.position {
                    case .leftSide:
                        leftShelfLayout
                    case .topBanner:
                        topBannerLayout
                    }
                }

                // Aperçu flottant du widget en cours de glissement
                if let dragged = draggedKind, let config = widgetManager.config(for: dragged) {
                    widgetView(for: config)
                        .scaleEffect(1.04)
                        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
                        .offset(
                            x: dragLocation.x - grabOffset.x,
                            y: dragLocation.y - grabOffset.y
                        )
                        .allowsHitTesting(false)
                        .zIndex(300)
                }
            }
            .coordinateSpace(name: "WidgetsAreaSpace")
            .onPreferenceChange(WidgetFramePreferenceKey.self) { frames in
                self.widgetFrames = frames
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: widgetManager.widgets)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: widgetManager.position)
        }
    }

    // MARK: - Disposition Volet Gauche (Inspiré de l'Image de Référence)

    private var leftShelfLayout: some View {
        let twoColumns = windowWidth >= 1050 && enabledWidgets.count > 2
        return Group {
            if twoColumns {
                HStack(alignment: .top, spacing: 14) {
                    // Première colonne (Ex: Vinyle en haut, Météo en bas)
                    let firstColumn = enabledWidgets.prefix(2)
                    VStack(spacing: 14) {
                        ForEach(firstColumn) { config in
                            widgetItem(for: config)
                        }
                    }

                    // Colonnes suivantes si d'autres widgets sont activés
                    let remaining = enabledWidgets.dropFirst(2)
                    if !remaining.isEmpty {
                        VStack(spacing: 14) {
                            ForEach(remaining) { config in
                                widgetItem(for: config)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(enabledWidgets) { config in
                        widgetItem(for: config)
                    }
                }
            }
        }
    }

    // MARK: - Disposition Bandeau Supérieur

    private var topBannerLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(enabledWidgets) { config in
                    widgetItem(for: config)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 195)
    }

    // MARK: - Élément Widget Interactif (Glisser-Déposer & Suppression)

    @ViewBuilder
    private func widgetItem(for config: CustomWidgetConfig) -> some View {
        let isBeingDragged = draggedKind == config.kind
        ZStack(alignment: .topLeading) {
            if isBeingDragged {
                // Emplacement fantôme (placeholder) pendant le déplacement
                RoundedRectangle(cornerRadius: widgetManager.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: widgetManager.cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    )
                    .frame(width: config.size.width, height: config.size.height)
            } else {
                widgetView(for: config)
                    .allowsHitTesting(!isEditing)
                    .contextMenu {
                        if !isEditing {
                            widgetContextMenu(for: config)
                        }
                    }
            }

            // Bouton de suppression en mode édition façon macOS
            if (isEditing || vm.showsDeleteBadges) && !isBeingDragged {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        widgetManager.toggleWidget(config.kind)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.96)))
                        .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1.2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
                .transition(.scale.combined(with: .opacity))
                .zIndex(200)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: WidgetFramePreferenceKey.self,
                    value: [config.kind: geo.frame(in: .named("WidgetsAreaSpace"))]
                )
            }
        )
        .modifier(JiggleEffect(active: isEditing && !isBeingDragged, phase: Double(config.order) * 0.2))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    if !vm.editing {
                        vm.setEditing(true)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(coordinateSpace: .named("WidgetsAreaSpace"))
                .onChanged { value in
                    if !vm.editing && hypot(value.translation.width, value.translation.height) > 6 {
                        vm.setEditing(true)
                    }
                    if draggedKind == nil {
                        draggedKind = config.kind
                        let startLoc = value.startLocation
                        let currentFrame = widgetFrames[config.kind] ?? CGRect(origin: startLoc, size: CGSize(width: config.size.width, height: config.size.height))
                        grabOffset = CGPoint(x: startLoc.x - currentFrame.minX, y: startLoc.y - currentFrame.minY)
                    }
                    if draggedKind == config.kind {
                        dragLocation = value.location

                        // Réordonnancement en temps réel lors du survol d'un autre widget
                        for (otherKind, frame) in widgetFrames where otherKind != config.kind {
                            if frame.contains(value.location) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    widgetManager.moveWidget(from: config.kind, to: otherKind)
                                }
                                break
                            }
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        draggedKind = nil
                        dragLocation = .zero
                        grabOffset = .zero
                    }
                }
        )
    }

    // MARK: - Rendu du Widget selon son type

    @ViewBuilder
    func widgetView(for config: CustomWidgetConfig) -> some View {
        switch config.kind {
        case .vinylPlayer:
            VinylPlayerWidgetView(config: config)
        case .weather:
            WeatherWidgetView(config: config)
        case .mediaWide:
            MediaWideWidgetView(config: config)
        case .clock:
            ClockWidgetView(config: config)
        case .system:
            SystemWidgetView(config: config)
        case .quickNote:
            QuickNoteWidgetView(config: config)
        }
    }

    // MARK: - Menu Contextuel Rapide par Widget

    @ViewBuilder
    private func widgetContextMenu(for config: CustomWidgetConfig) -> some View {
        Text(config.kind.title)
            .font(.headline)

        Divider()

        Menu(loc("widget.menu.change_size")) {
            ForEach(config.kind.allowedSizes) { size in
                Button(size.title) {
                    widgetManager.updateSize(for: config.kind, size: size)
                }
            }
        }

        Divider()

        Button(loc("widget.menu.remove"), role: .destructive) {
            widgetManager.toggleWidget(config.kind)
        }
    }
}

// MARK: - Préférence pour capturer les coordonnées des widgets

struct WidgetFramePreferenceKey: PreferenceKey {
    static var defaultValue: [WidgetKind: CGRect] = [:]
    static func reduce(value: inout [WidgetKind: CGRect], nextValue: () -> [WidgetKind: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
