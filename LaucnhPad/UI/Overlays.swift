import Combine
import SwiftUI
import AppKit

struct LaunchpadOverlays: View {
    @ObservedObject var vm: LaunchpadViewModel

    var body: some View {
        ZStack {
            if let dialog = vm.dialog {
                dimmer { vm.dialog = nil }
                ConfirmCard(dialog: dialog, onCancel: { vm.dialog = nil }, onConfirm: {
                    vm.dialog = nil
                    dialog.action()
                })
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let request = vm.rename {
                dimmer { vm.rename = nil; vm.textInputActive = false; vm.focusSearch() }
                RenameCard(request: request, vm: vm)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let session = vm.uninstall {
                dimmer { if !session.working { vm.uninstall = nil; vm.focusSearch() } }
                UninstallCard(session: session, onCancel: { vm.uninstall = nil; vm.focusSearch() }, onConfirm: { vm.confirmUninstall() })
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let modal = vm.customTileModal {
                dimmer { vm.customTileModal = nil; vm.focusSearch() }
                AddCustomTileCard(modal: modal, vm: vm)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let toast = vm.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule().strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.60), Color.white.opacity(0.15), Color.white.opacity(0.20)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                                )
                        }
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        .padding(.bottom, 90)
                        .frame(maxWidth: 560)
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.dialog?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.rename?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.uninstall?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.customTileModal?.id)
    }

    private func dimmer(_ action: @escaping () -> Void) -> some View {
        Color.black.opacity(0.35)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .ignoresSafeArea()
    }
}

private struct CardBackground: ViewModifier {
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass

    func body(content: Content) -> some View {
        content
            .padding(22)
            .background {
                if backgroundStyle == .liquidGlass {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.03), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.65),
                                            Color.white.opacity(0.22),
                                            Color.white.opacity(0.06),
                                            Color.white.opacity(0.22)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(white: 0.14).opacity(0.96))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.12)))
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 32, y: 14)
            .shadow(color: .black.opacity(0.20), radius: 6, y: 2)
    }
}

struct ConfirmCard: View {
    let dialog: DialogModel
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dialog.title).font(.headline).foregroundStyle(.white)
            Text(dialog.message).font(.callout).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(loc("dialog.cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(dialog.confirmTitle, role: dialog.destructive ? .destructive : nil, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .tint(dialog.destructive ? .red : .accentColor)
            }
        }
        .frame(width: 380)
        .modifier(CardBackground())
    }
}

struct RenameCard: View {
    let request: RenameRequest
    let vm: LaunchpadViewModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.isFolder ? loc("menu.rename_folder") : loc("dialog.rename")).font(.headline).foregroundStyle(.white)
            TextField(loc("overlay.name"), text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { vm.commitRename(text) }
            if !request.isFolder {
                Text(loc("overlay.rename_tip"))
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            HStack {
                Spacer()
                Button(loc("dialog.cancel")) { vm.rename = nil; vm.textInputActive = false; vm.focusSearch() }
                Button(loc("dialog.save")) { vm.commitRename(text) }.keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 380)
        .modifier(CardBackground())
        .onAppear {
            text = request.text
            vm.textInputActive = true
            DispatchQueue.main.async { focused = true }
        }
    }
}

struct UninstallCard: View {
    @ObservedObject var session: UninstallSession
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: IconCache.shared.icon(for: session.app.id)).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(loc("overlay.uninstall_confirm", session.app.name)).font(.headline).foregroundStyle(.white)
                        if !LicenseManager.shared.isPro {
                            ProBadge()
                        }
                    }
                    Text(loc("overlay.uninstall_trash_tip")).font(.caption).foregroundStyle(.white.opacity(0.65))
                }
            }
            if session.scanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(loc("overlay.uninstall_searching")).foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(session.files) { file in
                            Toggle(isOn: Binding(
                                get: { session.selected.contains(file.id) },
                                set: { isOn in
                                    if isOn { session.selected.insert(file.id) } else { session.selected.remove(file.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(file.kind).foregroundStyle(.white)
                                        Spacer()
                                        Text(Self.formatter.string(fromByteCount: file.size)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                                    }
                                    Text((file.url.path as NSString).abbreviatingWithTildeInPath)
                                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(file.isBundle)
                        }
                    }
                }
                .frame(maxHeight: 240)
                if session.isRunning {
                    Label(session.app.name, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.yellow)
                }
            }
            HStack {
                Text(loc("overlay.total", Self.formatter.string(fromByteCount: session.selectedSize)))
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button(loc("dialog.cancel"), action: onCancel).disabled(session.working)
                Button(role: .destructive, action: onConfirm) {
                    if session.working { ProgressView().controlSize(.small) } else { Text(loc("overlay.uninstall_trash_button")) }
                }
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(session.scanning || session.working || session.selected.isEmpty)
            }
        }
        .frame(width: 460)
        .modifier(CardBackground())
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
    @FocusState private var focusedField: Field?

    enum Field { case title, target }

    private let webSymbols = [
        "globe", "safari", "sparkles", "bubble.left.and.bubble.right.fill",
        "doc.text.fill", "chevron.left.forwardslash.chevron.right",
        "play.rectangle.fill", "cart.fill", "link", "newspaper.fill"
    ]

    private let shortcutSymbols = [
        "bolt.fill", "wand.and.stars", "play.fill", "gearshape.fill",
        "trash.fill", "folder.badge.gearshape", "music.note", "moon.fill",
        "camera.fill", "terminal.fill"
    ]

    private let colors = [
        "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F",
        "#FF453A", "#FF9F0A", "#30D158", "#63E6E2", "#64D2FF", "#8E8E93"
    ]

    init(modal: CustomTileModalModel, vm: LaunchpadViewModel) {
        self.modal = modal
        self.vm = vm
        _kind = State(initialValue: modal.kind)
        _symbol = State(initialValue: modal.kind == .web ? "globe" : "bolt.fill")
        _colorHex = State(initialValue: modal.kind == .web ? "#0A84FF" : "#5E5CE6")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(loc("overlay.custom_tile_add_title")).font(.headline).foregroundStyle(.white)
                Spacer()
                if !LicenseManager.shared.isPro {
                    ProBadge()
                }
            }

            Picker("", selection: $kind) {
                Text(loc("overlay.web_bookmark")).tag(CustomTile.Kind.web)
                Text(loc("overlay.apple_shortcut")).tag(CustomTile.Kind.shortcut)
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, newKind in
                if newKind == .web {
                    if !webSymbols.contains(symbol) { symbol = "globe" }
                    if colorHex == "#5E5CE6" { colorHex = "#0A84FF" }
                } else {
                    if !shortcutSymbols.contains(symbol) { symbol = "bolt.fill" }
                    if colorHex == "#0A84FF" { colorHex = "#5E5CE6" }
                }
            }

            // Aperçu interactif
            HStack(spacing: 16) {
                Image(nsImage: CustomTileRenderer.renderImage(symbol: symbol, colorHex: colorHex, size: 128))
                    .resizable()
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title.isEmpty ? (kind == .web ? loc("overlay.web_bookmark") : loc("overlay.apple_shortcut")) : title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(target.isEmpty ? (kind == .web ? "https://..." : loc("custom_tile.exact_name")) : target)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(loc("overlay.name")).font(.caption).foregroundStyle(.white.opacity(0.7))
                TextField(kind == .web ? "ex: ChatGPT, Notion, GitHub…" : "ex: Nettoyer le Bureau…", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .web ? loc("custom_tile.url_site") : loc("custom_tile.exact_name")).font(.caption).foregroundStyle(.white.opacity(0.7))
                TextField(kind == .web ? "https://chatgpt.com" : "Nom du raccourci macOS", text: $target)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .target)
            }

            // Choix du symbole
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("overlay.icon")).font(.caption).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 8) {
                    let symbols = kind == .web ? webSymbols : shortcutSymbols
                    ForEach(symbols, id: \.self) { sym in
                        Button {
                            symbol = sym
                        } label: {
                            Image(systemName: sym)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(symbol == sym ? .white : .white.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(symbol == sym ? Color.white.opacity(0.28) : Color.white.opacity(0.08))
                                 )
                                .overlay(
                                    Circle()
                                        .stroke(symbol == sym ? Color.white : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Choix de la couleur
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("overlay.color")).font(.caption).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 8) {
                    ForEach(colors, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(nsColor: NSColor(hexString: hex) ?? .systemBlue))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(colorHex == hex ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .scaleEffect(colorHex == hex ? 1.15 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button(loc("dialog.cancel")) {
                    vm.customTileModal = nil
                    vm.focusSearch()
                }
                .keyboardShortcut(.cancelAction)

                Button(loc("overlay.add")) {
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedTitle.isEmpty, !trimmedTarget.isEmpty else { return }
                    vm.addCustomTile(title: trimmedTitle, target: trimmedTarget, kind: kind, symbol: symbol, colorHex: colorHex)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(width: 440)
        .modifier(CardBackground())
        .onAppear { focusedField = .title }
    }
}
