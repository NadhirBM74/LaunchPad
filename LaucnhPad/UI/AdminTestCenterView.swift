import SwiftUI
import AppKit
import UserNotifications

// MARK: - Catégories du Centre de Test

enum AdminTestCategory: String, CaseIterable, Identifiable {
    case tutorial = "Tutoriel & Démarrage"
    case license = "Licence & Pro"
    case catalog = "Catalogue & Grille"
    case widgets = "Widgets & Tuiles"
    case music = "Simulation Musique"
    case appearance = "Thèmes & Logos"
    case display = "Affichage & Fenêtre"
    case notifications = "Notifications & Sons"
    case updates = "Mises à jour"
    case diagnostics = "Diagnostics & Logs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tutorial: return "graduationcap.fill"
        case .license: return "key.fill"
        case .catalog: return "square.grid.3x3.fill"
        case .widgets: return "puzzlepiece.extension.fill"
        case .music: return "opticaldisc.fill"
        case .appearance: return "paintpalette.fill"
        case .display: return "macwindow"
        case .notifications: return "bell.badge.fill"
        case .updates: return "arrow.triangle.2.circlepath.circle.fill"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

// MARK: - Fenêtre Dédiée du Centre de Test

@MainActor
final class AdminTestWindowController: NSObject, NSWindowDelegate {
    static let shared = AdminTestWindowController()

    private var window: NSWindow?
    private var isClosing = false

    var isVisible: Bool { window?.isVisible == true }

    func show(store: LaunchpadStore? = nil) {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "Centre de Test & Diagnostics — Mode Administrateur"
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.minSize = NSSize(width: 820, height: 560)
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.isMovableByWindowBackground = true
            self.window = win
        }

        guard let window else { return }
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: AdminTestCenterView(store: store))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }
}

// MARK: - Vue Complète du Centre de Test

struct AdminTestCenterView: View {
    var store: LaunchpadStore?

    @ObservedObject private var admin = AdminManager.shared
    @ObservedObject private var license = LicenseManager.shared
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var stats = SystemStatsMonitor.shared
    @ObservedObject private var widgetMgr = WidgetManager.shared
    @ObservedObject private var tileMgr = CustomTileManager.shared
    @ObservedObject private var musicMgr = MusicServiceManager.shared

    @State private var selectedCategory: AdminTestCategory = .tutorial
    @State private var previewTutorial = false
    @State private var previewStep = 0
    @State private var feedbackBanner: String? = nil
    @State private var feedbackTask: Task<Void, Never>? = nil

    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass
    @AppStorage(PrefKey.backgroundOpacity) private var backgroundOpacity: Double = 0.15
    @AppStorage(PrefKey.iconScale) private var iconScale: Double = 1.0
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons: Bool = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor: String = "accent"
    @AppStorage(PrefKey.appLogo) private var appLogoRaw: Int = AppLogo.noir.rawValue
    @AppStorage(PrefKey.displayMode) private var displayModeRaw: String = DisplayMode.fullScreen.rawValue
    @AppStorage(PrefKey.hideDock) private var hideDock: Bool = true
    @AppStorage(PrefKey.showWidgetBanner) private var showWidgetBanner: Bool = true
    @AppStorage(PrefKey.widgetBannerCollapsed) private var widgetBannerCollapsed: Bool = false

    @State private var soundFeedback = ""
    @State private var toastInput = "Message test depuis le Mode Admin"

    var body: some View {
        ZStack {
            HSplitView {
                sidebarView
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 280)

                mainContentView
                    .frame(minWidth: 540)
            }

            // Aperçu interactif du tutoriel en plein écran dans la fenêtre Admin
            if previewTutorial {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            previewTutorial = false
                        }
                    }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                previewTutorial = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 24)
                        .padding(.top, 20)
                    }

                    Spacer()

                    TutorialCardView(vm: nil, initialStepIndex: previewStep, onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            previewTutorial = false
                        }
                        triggerFeedback("Test du tutoriel complété avec succès")
                    })
                    .transition(.scale(scale: 0.94).combined(with: .opacity))

                    Spacer()
                }
                .zIndex(100)
            }
        }
        .frame(minWidth: 840, minHeight: 600)
    }

    // MARK: - Barre Latérale

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Entête Administrateur
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.35), Color.green.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.green.opacity(0.4), lineWidth: 1))

                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Mode Admin")
                            .font(.system(size: 13, weight: .bold))
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    }
                    Text(admin.authenticatedUser.isEmpty ? "admin" : admin.authenticatedUser)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 14)
            .background(Color.primary.opacity(0.03))

            Divider()

            List(AdminTestCategory.allCases, selection: $selectedCategory) { cat in
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedCategory == cat ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                            .frame(width: 26, height: 26)
                        Image(systemName: cat.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedCategory == cat ? Color.accentColor : Color.secondary)
                    }

                    Text(cat.rawValue)
                        .font(.system(size: 13, weight: selectedCategory == cat ? .semibold : .regular))

                    Spacer()
                }
                .tag(cat)
                .padding(.vertical, 3.5)
            }
            .listStyle(.sidebar)

            Divider()

            // Pied de barre latérale
            HStack {
                Button {
                    admin.logout()
                    AdminTestWindowController.shared.close()
                } label: {
                    Label("Verrouiller et Quitter", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))
        }
    }

    // MARK: - Contenu Principal

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Barre supérieure de titre et feedback
            HStack {
                categoryHeader(selectedCategory)
                Spacer()

                // Raccourci d'essai rapide du tutoriel
                Button {
                    previewStep = 0
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        previewTutorial = true
                    }
                } label: {
                    Label("Aperçu Tutoriel", systemImage: "graduationcap.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 12)
            .background(Color.primary.opacity(0.02))

            // Toast de feedback des actions
            if let feedbackBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(feedbackBanner)
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(8)
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedCategory {
                    case .tutorial: tutorialSection
                    case .license: licenseSection
                    case .catalog: catalogSection
                    case .widgets: widgetsSection
                    case .music: musicSection
                    case .appearance: appearanceSection
                    case .display: displaySection
                    case .notifications: notificationsSection
                    case .updates: updatesSection
                    case .diagnostics: diagnosticsSection
                    }
                }
                .padding(24)
            }
        }
    }

    // MARK: - En-tête de catégorie

    private func categoryHeader(_ category: AdminTestCategory) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: category.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.system(size: 18, weight: .bold))
                Text("Testez en direct les fonctionnalités et les sous-systèmes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 1. Tutoriel & Démarrage

    private var tutorialSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Carte principale : Essai du tutoriel
            testCard(title: "Essai Interactif du Tutoriel", subtitle: "Testez le guide d'accueil en direct avec animations, pagination et interaction.") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            previewStep = 0
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                previewTutorial = true
                            }
                            admin.log(category: "Tutoriel", message: "Ouverture de l'aperçu interactif du tutoriel")
                            triggerFeedback("Tutoriel interactif ouvert en mode aperçu")
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Tester le Tutoriel ici (Aperçu Interactif)")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)

                        Button {
                            admin.log(category: "Tutoriel", message: "Ouverture du tutoriel dans LaunchPad plein écran")
                            NotificationCenter.default.post(name: .openTutorial, object: nil)
                            triggerFeedback("Tutoriel lancé en plein écran dans LaunchPad")
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "macwindow.on.rectangle")
                                Text("Lancer en Plein Écran dans LaunchPad")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    Text("Tester directement une étape spécifique :")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    // Grille des étapes
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        stepButton(number: 1, title: "Bienvenue & Fluidité 120 FPS", icon: "sparkles", color: .blue, stepIndex: 0)
                        stepButton(number: 2, title: "Accès Rapide (⌃ Espace, Trackpad)", icon: "keyboard.fill", color: .green, stepIndex: 1)
                        stepButton(number: 3, title: "Organisation & Dossiers", icon: "square.grid.3x3.fill", color: .orange, stepIndex: 2)
                        stepButton(number: 4, title: "Recherche Instantanée au Clavier", icon: "magnifyingglass", color: .purple, stepIndex: 3)
                        stepButton(number: 5, title: "Widgets & Finitions Pro", icon: "crown.fill", color: .yellow, stepIndex: 4)
                    }
                }
            }

            // Gestion de l'état de premier lancement
            testCard(title: "Indicateur de Premier Lancement (hasLaunchedBefore)", subtitle: "Contrôlez le flag UserDefaults pour simuler un premier démarrage propre.") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("État actuel du compte :")
                            .font(.system(size: 13))

                        let hasLaunched = Prefs.defaults.bool(forKey: PrefKey.hasLaunchedBefore)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(hasLaunched ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(hasLaunched ? "Déjà lancé (hasLaunchedBefore = true)" : "Premier lancement en attente (hasLaunchedBefore = false)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(hasLaunched ? .green : .orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(hasLaunched ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        .cornerRadius(6)
                    }

                    HStack(spacing: 10) {
                        Button("Réinitialiser (hasLaunchedBefore = false)") {
                            Prefs.defaults.set(false, forKey: PrefKey.hasLaunchedBefore)
                            admin.log(category: "Tutoriel", message: "Flag hasLaunchedBefore réinitialisé à false")
                            triggerFeedback("Flag réinitialisé à false : le tutoriel s'affichera au prochain démarrage")
                        }
                        .buttonStyle(.bordered)

                        Button("Marquer comme complété (true)") {
                            Prefs.defaults.set(true, forKey: PrefKey.hasLaunchedBefore)
                            admin.log(category: "Tutoriel", message: "Flag hasLaunchedBefore marqué à true")
                            triggerFeedback("Flag défini sur true")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Prefs.defaults.set(false, forKey: PrefKey.hasLaunchedBefore)
                            admin.log(category: "Tutoriel", message: "Simulation complète d'un premier démarrage")
                            NotificationCenter.default.post(name: .openTutorial, object: nil)
                            triggerFeedback("Simulation premier lancement déclenchée")
                        } label: {
                            Label("Simuler Premier Démarrage Complet", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }
        }
    }

    private func stepButton(number: Int, title: String, icon: String, color: Color, stepIndex: Int) -> some View {
        Button {
            previewStep = stepIndex
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                previewTutorial = true
            }
            admin.log(category: "Tutoriel", message: "Test direct de l'étape \(number) : \(title)")
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Étape \(number)")
                        .font(.caption2.bold())
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Licence & Pro

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Contrôle du Statut Pro", subtitle: "Basculez entre la version Gratuite et la version Pro sans redémarrer.") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Statut Pro actuel :")
                        Text(license.isPro ? "DÉBLOQUÉ (PRO)" : "VERSION GRATUITE")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(license.isPro ? .green : .secondary)
                    }

                    HStack(spacing: 10) {
                        Button(license.isPro ? "Désactiver le Mode Pro" : "Activer le Mode Pro") {
                            if license.isPro {
                                license.deactivate()
                                admin.log(category: "Licence", message: "Désactivation du mode Pro")
                                triggerFeedback("Mode Pro désactivé (Version Gratuite)")
                            } else {
                                license.validate(code: "1234")
                                admin.log(category: "Licence", message: "Activation forcée du mode Pro")
                                triggerFeedback("Mode Pro activé avec succès")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(license.isPro ? .orange : .green)

                        Button("Valider la Clé '1234'") {
                            let res = license.validate(code: "1234")
                            admin.log(category: "Licence", message: "Validation clé 1234 : \(res.message)")
                            triggerFeedback("Clé 1234 validée avec succès")
                        }
                        .buttonStyle(.bordered)

                        Button("Tester Clé Invalide ('9999')") {
                            let res = license.validate(code: "9999")
                            admin.log(category: "Licence", message: "Test clé invalide : \(res.message)", isSuccess: false)
                            triggerFeedback("Erreur de clé simulée : \(res.message)")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            testCard(title: "Animation de Célébration Pro", subtitle: "Déclenche l'animation festive de passage à la version Pro.") {
                Button {
                    NotificationCenter.default.post(name: .openSettingsTab, object: SettingsPanel.SettingsTab.license)
                    admin.log(category: "Licence", message: "Ouverture de l'onglet Licence pour tester la célébration")
                    triggerFeedback("Onglet Licence ouvert dans les réglages")
                } label: {
                    Label("Ouvrir l'onglet Licence dans les Réglages", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 3. Catalogue & Grille

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Gestion du Catalogue d'Applications", subtitle: "Contrôlez l'indexation et l'organisation des applications.") {
                VStack(alignment: .leading, spacing: 12) {
                    if let store {
                        HStack(spacing: 20) {
                            Text("Applications indexées : **\(store.catalog.count)**")
                            Text("Éléments visibles : **\(store.visibleItems.count)**")
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            store?.refresh()
                            admin.log(category: "Catalogue", message: "Scan et rafraîchissement complet du catalogue")
                            triggerFeedback("Catalogue d'applications actualisé")
                        } label: {
                            Label("Actualiser le Catalogue", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Réorganiser de A à Z") {
                            Prefs.defaults.set(SortRule.nameAscending.rawValue, forKey: PrefKey.reorganizeRule)
                            store?.refresh()
                            admin.log(category: "Catalogue", message: "Réorganisation alphabétique A-Z")
                            triggerFeedback("Applications réorganisées par ordre alphabétique")
                        }
                        .buttonStyle(.bordered)

                        Button("Réorganiser par Catégorie") {
                            Prefs.defaults.set(SortRule.category.rawValue, forKey: PrefKey.reorganizeRule)
                            store?.refresh()
                            admin.log(category: "Catalogue", message: "Réorganisation par catégorie")
                            triggerFeedback("Applications réorganisées par catégorie")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Ajouter une Tuile Web de Démo (Apple)") {
                        tileMgr.addTile(title: "Apple Démo", target: "https://apple.com", kind: .web, symbol: "apple.logo", colorHex: "FFFFFF")
                        store?.refresh()
                        admin.log(category: "Catalogue", message: "Ajout d'un signet Web Apple de test")
                        triggerFeedback("Signet Web Apple ajouté au catalogue")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - 4. Widgets & Tuiles

    private var widgetsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Bannière de Widgets Supérieure", subtitle: "Afficher, masquer ou replier la barre de widgets intégrée.") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Afficher la bannière de widgets", isOn: $showWidgetBanner)
                    Toggle("Bannière repliée", isOn: $widgetBannerCollapsed)
                }
            }

            testCard(title: "Widgets Personnalisés", subtitle: "Ajoutez ou réinitialisez les widgets de test sur le bureau.") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Widgets actifs : **\(widgetMgr.widgets.count)**")

                    HStack(spacing: 10) {
                        Button("Ajouter Widget Vinyle") {
                            let config = CustomWidgetConfig(kind: .vinylPlayer, size: .medium)
                            widgetMgr.widgets.append(config)
                            widgetMgr.saveSettings()
                            store?.refresh()
                            admin.log(category: "Widgets", message: "Ajout d'un widget Platine Vinyle")
                            triggerFeedback("Widget Platine Vinyle ajouté")
                        }
                        .buttonStyle(.bordered)

                        Button("Ajouter Widget Horloge") {
                            let config = CustomWidgetConfig(kind: .clock, size: .small)
                            widgetMgr.widgets.append(config)
                            widgetMgr.saveSettings()
                            store?.refresh()
                            admin.log(category: "Widgets", message: "Ajout d'un widget Horloge")
                            triggerFeedback("Widget Horloge ajouté")
                        }
                        .buttonStyle(.bordered)

                        Button("Ajouter Widget Système") {
                            let config = CustomWidgetConfig(kind: .system, size: .medium)
                            widgetMgr.widgets.append(config)
                            widgetMgr.saveSettings()
                            store?.refresh()
                            admin.log(category: "Widgets", message: "Ajout d'un widget Moniteur Système")
                            triggerFeedback("Widget Moniteur Système ajouté")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Restaurer les widgets par défaut") {
                        widgetMgr.widgets = WidgetManager.defaultWidgets()
                        widgetMgr.saveSettings()
                        store?.refresh()
                        admin.log(category: "Widgets", message: "Restauration des widgets par défaut")
                        triggerFeedback("Widgets restaurés par défaut")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - 5. Simulation Musique

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Simulateur de Piste en Cours (Now Playing)", subtitle: "Permet de tester l'affichage et l'animation du widget Vinyle sans lancer de lecteur.") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Piste actuelle :")
                        Text(musicMgr.currentTrack.title.isEmpty ? "Aucune lecture" : "\(musicMgr.currentTrack.title) — \(musicMgr.currentTrack.artist)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button("Daft Punk - One More Time") {
                            admin.log(category: "Musique", message: "Simulation piste Daft Punk")
                            musicMgr.alertMessage = "Simulation Daft Punk"
                            triggerFeedback("Morceau simulé : Daft Punk - One More Time")
                        }
                        .buttonStyle(.bordered)

                        Button("The Weeknd - Blinding Lights") {
                            admin.log(category: "Musique", message: "Simulation piste The Weeknd")
                            musicMgr.alertMessage = "Simulation The Weeknd"
                            triggerFeedback("Morceau simulé : The Weeknd - Blinding Lights")
                        }
                        .buttonStyle(.bordered)

                        Button("Ouvrir l'application Musique") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
                            admin.log(category: "Musique", message: "Ouverture de l'application Musique macOS")
                            triggerFeedback("Application Musique macOS lancée")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    // MARK: - 6. Thèmes & Logos

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Thème Visuel", subtitle: "Changement dynamique du thème d'arrière-plan.") {
                Picker("Thème :", selection: $backgroundStyle) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            testCard(title: "Logo de l'Application", subtitle: "Changement de l'icône de l'application parmi les 6 designs exclusifs.") {
                HStack(spacing: 16) {
                    ForEach(AppLogo.allCases) { logo in
                        VStack(spacing: 6) {
                            if let img = logo.image {
                                Image(nsImage: img)
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(appLogoRaw == logo.rawValue ? Color.accentColor : Color.clear, lineWidth: 2.5)
                                    )
                            }
                            Text(logo.title)
                                .font(.caption2)
                        }
                        .onTapGesture {
                            appLogoRaw = logo.rawValue
                            NSApp.applicationIconImage = logo.image
                            admin.log(category: "Logo", message: "Sélection du logo : \(logo.title)")
                            triggerFeedback("Logo d'application changé : \(logo.title)")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            testCard(title: "Icônes Teintées & Échelle", subtitle: "Ajustez les effets graphiques de la grille.") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Icônes teintées", isOn: $tintedIcons)

                    HStack {
                        Text("Échelle des icônes : \(Int(iconScale * 100))%")
                        Slider(value: $iconScale, in: 0.7...1.4, step: 0.05)
                    }

                    HStack {
                        Text("Opacité du fond : \(Int(backgroundOpacity * 100))%")
                        Slider(value: $backgroundOpacity, in: 0.0...0.8, step: 0.05)
                    }
                }
            }
        }
    }

    // MARK: - 7. Affichage & Fenêtre

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Mode de Fenêtrage", subtitle: "Contrôlez la présentation de LaunchPad.") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Mode :", selection: $displayModeRaw) {
                        Text("Plein écran").tag(DisplayMode.fullScreen.rawValue)
                        Text("Fenêtre centrée").tag(DisplayMode.window.rawValue)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Masquer automatiquement le Dock macOS en plein écran", isOn: $hideDock)

                    HStack(spacing: 10) {
                        Button("Ouvrir LaunchPad") {
                            NotificationCenter.default.post(name: .launchpadVisibilityDidChange, object: true)
                            admin.log(category: "Affichage", message: "Demande d'ouverture du LaunchPad")
                            triggerFeedback("LaunchPad ouvert")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Fermer LaunchPad") {
                            NotificationCenter.default.post(name: .launchpadVisibilityDidChange, object: false)
                            admin.log(category: "Affichage", message: "Demande de fermeture du LaunchPad")
                            triggerFeedback("LaunchPad fermé")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - 8. Notifications & Sons

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Sons Système macOS", subtitle: "Testez les différents effets sonores de retour.") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(["Glass", "Ping", "Pop", "Purr", "Tink", "Submarine"], id: \.self) { sound in
                            Button(sound) {
                                NSSound(named: sound)?.play()
                                soundFeedback = "Lecture du son : \(sound)"
                                admin.log(category: "Son", message: "Lecture du son système : \(sound)")
                                triggerFeedback("Son joué : \(sound)")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if !soundFeedback.isEmpty {
                        Text(soundFeedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            testCard(title: "Notification Toast dans LaunchPad", subtitle: "Affiche un message flottant à l'intérieur de LaunchPad.") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Message du toast", text: $toastInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Envoyer le Toast dans LaunchPad") {
                        NotificationCenter.default.post(name: .triggerTestToast, object: toastInput)
                        admin.log(category: "Toast", message: "Envoi du toast : '\(toastInput)'")
                        triggerFeedback("Toast envoyé à LaunchPad : \(toastInput)")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            testCard(title: "Notification Système macOS", subtitle: "Envoie une notification native via le Centre de Notifications.") {
                Button("Envoyer une Notification Système de Test") {
                    let content = UNMutableNotificationContent()
                    content.title = "LaunchPad Admin"
                    content.body = "Ceci est une notification de test générée avec succès depuis le Mode Administrateur."
                    content.sound = .default

                    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(req)
                    admin.log(category: "Notification", message: "Notification macOS envoyée au système")
                    triggerFeedback("Notification système envoyée")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 9. Mises à jour

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Simulateur d'États de Mise à Jour", subtitle: "Forcez l'UpdateManager dans un état particulier pour tester l'interface utilisateur.") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Button("Normal (Idle)") {
                            updates.setDebugState(.idle)
                            admin.log(category: "Update", message: "État défini sur .idle")
                            triggerFeedback("État UpdateManager : .idle")
                        }
                        .buttonStyle(.bordered)

                        Button("Recherche en cours...") {
                            updates.setDebugState(.checking)
                            admin.log(category: "Update", message: "État défini sur .checking")
                            triggerFeedback("État UpdateManager : .checking")
                        }
                        .buttonStyle(.bordered)

                        Button("À jour (v1.0.2)") {
                            updates.setDebugState(.upToDate(version: "1.0.2"))
                            admin.log(category: "Update", message: "État défini sur .upToDate")
                            triggerFeedback("État UpdateManager : .upToDate")
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 8) {
                        Button("Mise à jour dispo (v2.0.0)") {
                            updates.setDebugState(.updateAvailable(version: "2.0.0", notes: "### 🚀 Nouveautés v2.0.0\n- Mode Administrateur complet\n- Nouveau tutoriel interactif\n- Améliorations de fluidité", downloadUrl: nil))
                            admin.log(category: "Update", message: "État défini sur .updateAvailable (v2.0.0)")
                            triggerFeedback("État UpdateManager : .updateAvailable (v2.0.0)")
                        }
                        .buttonStyle(.bordered)

                        Button("Téléchargement (65%)") {
                            updates.setDebugState(.downloading(progress: 0.65))
                            admin.log(category: "Update", message: "État défini sur .downloading (65%)")
                            triggerFeedback("État UpdateManager : .downloading (65%)")
                        }
                        .buttonStyle(.bordered)

                        Button("Prêt à redémarrer") {
                            updates.setDebugState(.readyToRestart(version: "2.0.0"))
                            admin.log(category: "Update", message: "État défini sur .readyToRestart")
                            triggerFeedback("État UpdateManager : .readyToRestart")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - 10. Diagnostics & Logs

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCard(title: "Performances & Système en Direct", subtitle: "Lecture instantanée des ressources matérielles.") {
                HStack(spacing: 20) {
                    statBox(title: "CPU", value: "\(stats.cpuPercent)%", icon: "cpu")
                    statBox(title: "RAM Utilisée", value: "\(stats.ramPercent)%", icon: "memorychip")
                    statBox(title: "RAM (Go)", value: String(format: "%.1f / %.1f Go", stats.ramUsedGB, stats.ramTotalGB), icon: "internaldrive")
                    statBox(title: "Batterie", value: "\(stats.batteryPercent)%", icon: "battery.100")
                }
            }

            testCard(title: "Informations Système", subtitle: "Détails techniques de l'environnement.") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Version macOS : **\(ProcessInfo.processInfo.operatingSystemVersionString)**")
                    Text("• Nombre de cœurs CPU : **\(ProcessInfo.processInfo.processorCount)**")
                    if let mainScreen = NSScreen.main {
                        Text("• Résolution écran principal : **\(Int(mainScreen.frame.width)) x \(Int(mainScreen.frame.height))**")
                    }
                }
                .font(.system(size: 12))
            }

            testCard(title: "Journal des Événements & Tests (\(admin.testLogs.count))", subtitle: "Historique en temps réel des actions de test exécutées.") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button("Effacer les logs") {
                            admin.clearLogs()
                            triggerFeedback("Journal de logs effacé")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(admin.testLogs) { log in
                                HStack(spacing: 8) {
                                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text("[\(log.category)]")
                                        .font(.caption2.bold())
                                        .foregroundStyle(log.isSuccess ? Color.blue : Color.red)
                                    Text(log.message)
                                        .font(.caption)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(height: 180)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Feedback Toast Helper

    private func triggerFeedback(_ text: String) {
        feedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            feedbackBanner = text
        }
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                feedbackBanner = nil
            }
        }
    }

    // MARK: - Composants Utilitaires

    private func testCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func statBox(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
}
