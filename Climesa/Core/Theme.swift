import SwiftUI

// MARK: - Tokens de diseño (tomados de las pantallas "iOS / Acceso")

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let navy = Color(hex: 0x171A2D)
    static let lime = Color(hex: 0xE4F28C)
    static let background = Color(hex: 0xF6F4EF)
    static let blue = Color(hex: 0x3350E0)
    static let ink = Color(hex: 0x15172A)
    static let muted = Color(hex: 0x6B6E7A)
    static let line = Color(hex: 0xE3E1DC)
    static let errorBg = Color(hex: 0xFDEEEE)
    static let errorText = Color(hex: 0xB3263A)
    static let infoBg = Color(hex: 0xF0F5D9)
    static let card = Color.white
    static let okText = Color(hex: 0x3F6B12)
}

enum Appearance {
    static func configure() {
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = UIColor(Theme.background)
        a.shadowColor = UIColor(Theme.line)
        let normal = UIColor(Theme.muted)
        let selected = UIColor(Theme.blue)
        for item in [a.stackedLayoutAppearance, a.inlineLayoutAppearance, a.compactInlineLayoutAppearance] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal, .font: UIFont.systemFont(ofSize: 9)]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected, .font: UIFont.systemFont(ofSize: 9, weight: .medium)]
        }
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }
}

// MARK: - Encabezado con logotipo

struct ClimesaHeader<Trailing: View>: View {
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Theme.lime
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(Theme.navy)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                Text("climesa")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.9)
                    .foregroundColor(.white)
                Text("Hospital universitario")
                    .font(.system(size: 6.5))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(Theme.navy.ignoresSafeArea(edges: .top))
    }
}

// MARK: - Tipografía

struct MonoLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(Theme.blue)
    }
}

struct HeadlineText: View {
    let text: String
    var size: CGFloat = 36
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .tracking(-size * 0.04)
            .lineSpacing(-size * 0.06)
            .foregroundColor(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct BodyText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(Theme.muted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Botones

struct PrimaryButton: View {
    let title: String
    var isEnabled = true
    var tint: Color = Theme.blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(tint.opacity(isEnabled ? 1 : 0.75))
        }
        .disabled(!isEnabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.blue)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(Rectangle().stroke(Theme.blue, lineWidth: 1))
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct LinkButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.blue)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Avisos

struct Banner: View {
    enum Kind { case error, info }
    let kind: Kind
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .lineSpacing(3)
            .foregroundColor(kind == .error ? Theme.errorText : Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(kind == .error ? Theme.errorBg : Theme.infoBg)
    }
}

struct Pill: View {
    let text: String
    var fg: Color = Theme.ink
    var bg: Color = Theme.infoBg
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
    }
}

// MARK: - Formularios

enum AuthField: Hashable { case name, email, password, confirm }

struct FormCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 4) { content() }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Theme.card)
    }
}

/// Campo con subrayado; al enfocarse se dibuja como caja (como "Nombre completo" en el diseño).
struct ClimesaField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .never
    let field: AuthField
    var focus: FocusState<AuthField?>.Binding

    var body: some View {
        let isFocused = focus.wrappedValue == field
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.muted)
            Group {
                if secure {
                    SecureField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.ink.opacity(0.8)))
                } else {
                    TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.ink.opacity(0.8)))
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(capitalization)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .font(.system(size: 14))
            .foregroundColor(Theme.ink)
            .tint(Theme.blue)
            .focused(focus, equals: field)
            .frame(minHeight: 22)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if isFocused { Rectangle().stroke(Theme.line, lineWidth: 1) }
        }
        .overlay(alignment: .bottom) {
            if !isFocused {
                Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = field }
    }
}

/// Campo simple (hojas y formularios internos).
struct PlainField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 10.5)).foregroundColor(Theme.muted)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.muted.opacity(0.7)), axis: axis)
                .lineLimit(axis == .vertical ? 2...5 : 1...1)
                .font(.system(size: 14))
                .foregroundColor(Theme.ink)
                .tint(Theme.blue)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .padding(.vertical, 6)
    }
}


// MARK: - Contenedores de pantalla

struct ScreenScaffold<Content: View>: View {
    let label: String
    let title: String
    var subtitle: String? = nil
    var titleSize: CGFloat = 30
    var refresh: (() async -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel(text: label).padding(.top, 24)
                HeadlineText(text: title, size: titleSize).padding(.top, 14)
                if let subtitle { BodyText(text: subtitle).padding(.top, 12) }
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refresh?() }
        .background(Theme.background)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(Theme.muted)
            .padding(.top, 8)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
    }
}

struct SheetScaffold<Content: View>: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 18, weight: .bold)).tracking(-0.5).foregroundColor(Theme.ink)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .font(.system(size: 13)).foregroundColor(Theme.blue)
            }
            .padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }
}
