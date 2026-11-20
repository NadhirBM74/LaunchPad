import Combine
import SwiftUI
import AppKit

struct LaunchpadOverlays: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject private var permissionManager = PermissionManager.shared

    var body: some View {
        LaunchpadOverlaysContent(
            dialog: vm.dialog,
            rename: vm.rename,
            uninstall: vm.uninstall,
            customTileModal: vm.customTileModal,
            showTutorial: vm.showTutorial,
            toast: vm.toast,
            showPermissionBanner: permissionManager.showPermissionCard && !permissionManager.isAccessibilityGranted,
            vm: vm,
            permissionManager: permissionManager
        )
        .equatable()
    }
}

private struct LaunchpadOverlaysContent: View, Equatable {
    let dialog: DialogModel?
    let rename: RenameRequest?
    let uninstall: UninstallSession?
    let customTileModal: CustomTileModalModel?
    let showTutorial: Bool
    let toast: String?
    let showPermissionBanner: Bool
    let vm: LaunchpadViewModel
    let permissionManager: PermissionManager

    static func == (lhs: LaunchpadOverlaysContent, rhs: LaunchpadOverlaysContent) -> Bool {
        lhs.dialog?.id == rhs.dialog?.id
            && lhs.rename?.id == rhs.rename?.id
            && lhs.uninstall?.id == rhs.uninstall?.id
            && lhs.customTileModal?.id == rhs.customTileModal?.id
            && lhs.showTutorial == rhs.showTutorial
            && lhs.toast == rhs.toast
            && lhs.showPermissionBanner == rhs.showPermissionBanner
    }

    var body: some View {
        ZStack {
            if let dialog {
                dimmer()
                ConfirmCard(dialog: dialog, onConfirm: {
                    vm.dialog = nil
                    dialog.action()
                })
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let request = rename {
                dimmer()
                RenameCard(request: request, vm: vm)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let session = uninstall {
                dimmer()
                UninstallCard(session: session, onConfirm: { vm.confirmUninstall() })
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let modal = customTileModal {
                dimmer()
                AddCustomTileCard(modal: modal, vm: vm)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if showTutorial {
                TutorialModalView(vm: vm)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            if showPermissionBanner {
                dimmer()
                AccessibilityPermissionCard()
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .liquidGlassCapsule()
                        .shadow(color: LiquidGlassStyle.shadowColor, radius: 14, y: 6)
                        .padding(.bottom, 90)
                        .frame(maxWidth: 560)
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: dialog?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: rename?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: uninstall?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: customTileModal?.id)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showTutorial)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showPermissionBanner)
    }

    private func dimmer() -> some View {
        Color.black.opacity(0.45)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}

struct ConfirmCard: View {
    let dialog: DialogModel
    let onConfirm: () -> Void

    var body: some View {
        VelvetAuraModalContainer(cornerRadius: 20) { aura in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Text(dialog.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(aura.primaryText)
                    Spacer(minLength: 8)
                    VelvetAuraEscapePill()
                }
                Text(dialog.message)
                    .font(.system(size: 13))
                    .foregroundStyle(aura.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !dialog.confirmTitle.isEmpty {
                    HStack {
                        Spacer()
                        Button(action: onConfirm) {
                            Text(dialog.confirmTitle)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(
                                    dialog.destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(aura.accentGradient),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(22)
            .frame(width: 410)
        }
    }
}

struct RenameCard: View {
    let request: RenameRequest
    let vm: LaunchpadViewModel
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VelvetAuraModalContainer(cornerRadius: 20) { aura in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Text(request.isFolder ? loc("menu.rename_folder") : loc("dialog.rename"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(aura.primaryText)
                    Spacer(minLength: 8)
                    VelvetAuraEscapePill()
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField(loc("overlay.name"), text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .foregroundStyle(aura.primaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(aura.pillFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(aura.pillBorder, lineWidth: 1))
                        .focused($focused)
                        .onSubmit { vm.commitRename(text) }

                    if !request.isFolder {
                        Text(loc("overlay.rename_tip"))
                            .font(.caption)
                            .foregroundStyle(aura.secondaryText)
                    }
                }
                .padding(12)
                .background(VelvetAuraCardBackground(theme: backgroundStyle, cornerRadius: 14))
                .overlay(VelvetAuraCardOverlay(theme: backgroundStyle, cornerRadius: 14))

                HStack {
                    Spacer()
                    Button {
                        vm.commitRename(text)
                    } label: {
                        Text(loc("dialog.save"))
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(aura.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 410)
        }
        .onAppear {
            text = request.text
            vm.textInputActive = true
            DispatchQueue.main.async { focused = true }
        }
    }
}

struct UninstallCard: View {
    @ObservedObject var session: UninstallSession
    let onConfirm: () -> Void
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VelvetAuraModalContainer(cornerRadius: 22) { aura in
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    LiveAppIconView(image: IconCache.shared.icon(for: session.app.id), size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text(loc("overlay.uninstall_confirm", session.app.name))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(aura.primaryText)
                                .lineLimit(1)
                            if !LicenseManager.shared.isPro {
                                ProBadge()
                            }
                        }
                        Text(loc("overlay.uninstall_trash_tip"))
                            .font(.system(size: 12))
                            .foregroundStyle(aura.secondaryText)
                    }
                    Spacer(minLength: 8)
                    VelvetAuraEscapePill()
                }

                Rectangle()
                    .fill(aura.divider)
                    .frame(height: 1)

                Group {
                    if session.scanning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(loc("overlay.uninstall_searching"))
                                .foregroundStyle(aura.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 90)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(session.files) { file in
                                    Toggle(isOn: Binding(
                                        get: { session.selected.contains(file.id) },
                                        set: { isOn in
                                            if isOn { session.selected.insert(file.id) } else { session.selected.remove(file.id) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(file.kind)
                                                    .font(.system(size: 12.5, weight: .semibold))
                                                    .foregroundStyle(aura.primaryText)
                                                Spacer()
                                                Text(Self.formatter.string(fromByteCount: file.size))
                                                    .font(.system(size: 11.5, weight: .medium))
                                                    .foregroundStyle(aura.secondaryText)
                                                    .monospacedDigit()
                                            }
                                            Text((file.url.path as NSString).abbreviatingWithTildeInPath)
                                                .font(.caption2)
                                                .foregroundStyle(aura.secondaryText.opacity(0.8))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .tint(aura.accent)
                                    .disabled(file.isBundle)
                                }
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                }
                .padding(14)
                .background(VelvetAuraCardBackground(theme: backgroundStyle, cornerRadius: 15))
                .overlay(VelvetAuraCardOverlay(theme: backgroundStyle, cornerRadius: 15))

                if session.isRunning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(session.app.name)
                            .font(.caption)
                            .foregroundStyle(aura.primaryText)
                    }
                }

                HStack {
                    Text(loc("overlay.total", Self.formatter.string(fromByteCount: session.selectedSize)))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(aura.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(aura.pillFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(aura.pillBorder, lineWidth: 0.8))

                    Spacer()

                    Button(action: onConfirm) {
                        HStack(spacing: 6) {
                            if session.working {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(loc("overlay.uninstall_trash_button"))
                                    .font(.system(size: 12.5, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red, in: Capsule())
                        .shadow(color: Color.red.opacity(0.35), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.scanning || session.working || session.selected.isEmpty)
                }
            }
            .padding(22)
            .frame(width: 520)
        }
    }
}

// MARK: - Carte d'ajout de signet ou raccourci (Pro)

struct AddCustomTileCard: View {
    let modal: CustomTileModalModel
    let vm: LaunchpadViewModel

    @State private var kind: CustomTile.Kind
    @State private var title = ""
    @State private var target = ""
    @State private var symbol: String
    @State private var colorHex: String
    @State private var previewImage: NSImage
    @FocusState private var focusedField: Field?

    enum Field { case title, target }

    private static let webSymbols = [
        "globe", "safari", "sparkles", "bubble.left.and.bubble.right.fill",
        "doc.text.fill", "chevron.left.forwardslash.chevron.right",
        "play.rectangle.fill", "cart.fill", "link", "newspaper.fill"
    ]

    private static let shortcutSymbols = [
        "bolt.fill", "wand.and.stars", "play.fill", "gearshape.fill",
        "trash.fill", "folder.badge.gearshape", "music.note", "moon.fill",
        "camera.fill", "terminal.fill"
    ]

    private static let colorSwatches: [(hex: String, color: Color)] = [
        "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F",
        "#FF453A", "#FF9F0A", "#30D158", "#63E6E2", "#64D2FF", "#8E8E93"
    ].map { ($0, Color(nsColor: NSColor(hexString: $0) ?? .systemBlue)) }

    private var symbolsList: [String] { kind == .web ? Self.webSymbols : Self.shortcutSymbols }

    init(modal: CustomTileModalModel, vm: LaunchpadViewModel) {
        self.modal = modal
        self.vm = vm
        let initialSym = modal.kind == .web ? "globe" : "bolt.fill"
        let initialHex = modal.kind == .web ? "#0A84FF" : "#5E5CE6"
        _kind = State(initialValue: modal.kind)
        _symbol = State(initialValue: initialSym)
        _colorHex = State(initialValue: initialHex)
        _previewImage = State(initialValue: CustomTileRenderer.renderImage(symbol: initialSym, colorHex: initialHex, size: 128))
    }

    var body: some View {
        VelvetAuraModalContainer(cornerRadius: 22) { aura in
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 8) {
                    Text(loc("overlay.custom_tile_add_title"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(aura.primaryText)
                    if !LicenseManager.shared.isPro {
                        ProBadge()
                    }
                    Spacer(minLength: 8)
                    VelvetAuraEscapePill()
                }

                Picker("", selection: $kind) {
                    Text(loc("overlay.web_bookmark")).tag(CustomTile.Kind.web)
                    Text(loc("overlay.apple_shortcut")).tag(CustomTile.Kind.shortcut)
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, newKind in
                    if newKind == .web {
                        if !Self.webSymbols.contains(symbol) { symbol = "globe" }
                        if colorHex == "#5E5CE6" { colorHex = "#0A84FF" }
                    } else {
                        if !Self.shortcutSymbols.contains(symbol) { symbol = "bolt.fill" }
                        if colorHex == "#0A84FF" { colorHex = "#5E5CE6" }
                    }
                }

                // Aperçu interactif
                HStack(spacing: 16) {
                    Image(nsImage: previewImage)
                        .resizable()
                        .frame(width: 58, height: 58)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        .onChange(of: symbol) { _, newSym in
                            previewImage = CustomTileRenderer.renderImage(symbol: newSym, colorHex: colorHex, size: 128)
                        }
                        .onChange(of: colorHex) { _, newHex in
                            previewImage = CustomTileRenderer.renderImage(symbol: symbol, colorHex: newHex, size: 128)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title.isEmpty ? (kind == .web ? loc("overlay.web_bookmark") : loc("overlay.apple_shortcut")) : title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(aura.primaryText)
                        Text(target.isEmpty ? (kind == .web ? "https://..." : loc("custom_tile.exact_name")) : target)
                            .font(.system(size: 12))
                            .foregroundStyle(aura.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(aura.pillFill, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(aura.pillBorder, lineWidth: 0.8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("overlay.name")).font(.caption).foregroundStyle(aura.secondaryText)
                    TextField(kind == .web ? loc("custom_tile.web_example") : loc("custom_tile.shortcut_example"), text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(aura.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(aura.pillFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(aura.pillBorder, lineWidth: 0.9))
                        .focused($focusedField, equals: .title)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(kind == .web ? loc("custom_tile.url_site") : loc("custom_tile.exact_name"))
                        .font(.caption)
                        .foregroundStyle(aura.secondaryText)
                    TextField(kind == .web ? "https://chatgpt.com" : loc("custom_tile.shortcut_name_placeholder"), text: $target)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(aura.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(aura.pillFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(aura.pillBorder, lineWidth: 0.9))
                        .focused($focusedField, equals: .target)
                }

                // Choix du symbole
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("overlay.icon")).font(.caption).foregroundStyle(aura.secondaryText)
                    HStack(spacing: 8) {
                        ForEach(symbolsList, id: \.self) { sym in
                            Button {
                                symbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(symbol == sym ? .white : aura.secondaryText)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(symbol == sym ? AnyShapeStyle(aura.accentGradient) : AnyShapeStyle(aura.pillFill))
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(symbol == sym ? aura.accent : aura.pillBorder, lineWidth: symbol == sym ? 1.5 : 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Choix de la couleur
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("overlay.color")).font(.caption).foregroundStyle(aura.secondaryText)
                    HStack(spacing: 8) {
                        ForEach(Self.colorSwatches, id: \.hex) { swatch in
                            Button {
                                colorHex = swatch.hex
                            } label: {
                                Circle()
                                    .fill(swatch.color)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(colorHex == swatch.hex ? aura.primaryText : Color.clear, lineWidth: 2)
                                    )
                                    .scaleEffect(colorHex == swatch.hex ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTitle.isEmpty, !trimmedTarget.isEmpty else { return }
                        vm.addCustomTile(title: trimmedTitle, target: trimmedTarget, kind: kind, symbol: symbol, colorHex: colorHex)
                    } label: {
                        Text(loc("overlay.add"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(aura.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(22)
            .frame(width: 470)
        }
        .onAppear { focusedField = .title }
    }
}

// MARK: - Carte d'autorisation d'Accessibilité (Aura Nocturne Velvet 4C)

struct AccessibilityPermissionCard: View {
    @ObservedObject private var permissionManager = PermissionManager.shared

    var body: some View {
        VelvetAuraModalContainer(cornerRadius: 22) { aura in
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    VelvetAuraEscapePill()
                }

                // Icône avec halo lumineux
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(Circle().strokeBorder(Color.orange.opacity(0.45), lineWidth: 1))
                        .shadow(color: Color.orange.opacity(0.28), radius: 10, y: 3)

                    Image(systemName: "hand.raised.app.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                VStack(spacing: 6) {
                    Text(loc("permission.accessibility.title"))
                        .font(.system(size: 17.5, weight: .bold))
                        .foregroundStyle(aura.primaryText)
                        .multilineTextAlignment(.center)

                    Text(loc("permission.accessibility.subtitle"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(aura.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Liste des fonctionnalités nécessitant l'autorisation
                VStack(alignment: .leading, spacing: 10) {
                    featureRow(icon: "hand.draw.fill", title: loc("permission.feature.pinch"), desc: loc("permission.feature.pinch_desc"), aura: aura)
                    featureRow(icon: "keyboard.fill", title: loc("permission.feature.f4"), desc: loc("permission.feature.f4_desc"), aura: aura)
                    featureRow(icon: "cursorarrow.rays", title: loc("permission.feature.hotcorner"), desc: loc("permission.feature.hotcorner_desc"), aura: aura)
                    featureRow(icon: "playpause.fill", title: loc("permission.feature.media"), desc: loc("permission.feature.media_desc"), aura: aura)
                }
                .padding(14)
                .background(aura.pillFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(aura.pillBorder, lineWidth: 1))

                if permissionManager.isAccessibilityGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(loc("permission.granted_auto"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity)
                } else {
                    Button {
                        permissionManager.requestAccessibility()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12))
                            Text(loc("general.accessibility_button"))
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(aura.accentGradient, in: Capsule())
                        .shadow(color: aura.accent.opacity(0.35), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
            .frame(width: 460)
        }
    }

    private func featureRow(icon: String, title: String, desc: String, aura: VelvetAuraTheme) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(aura.primaryText)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(aura.secondaryText)
            }
            Spacer()
        }
    }
}
