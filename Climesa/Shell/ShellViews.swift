import SwiftUI

/// Interruptores de entrega. Los módulos clínicos ya existen (ConsultationView, LabView),
/// pero el diseño los marca como "próxima entrega"; ponlo en `true` para activarlos.
enum FeatureFlags {
    static let clinicalModulesEnabled = false
}

enum ShellTab: Hashable {
    case home, consult, shifts, appointments, results, account

    var icon: String {
        switch self {
        case .home: return "house"
        case .consult, .results: return "list.bullet"
        case .shifts, .appointments: return "calendar"
        case .account: return "person"
        }
    }

    func title(in area: Area) -> String {
        switch self {
        case .home: return "Inicio"
        case .consult: return "Consultas"
        case .shifts: return "Mis turnos"
        case .appointments: return "Citas"
        case .results: return "Resultados"
        case .account: return "Mi cuenta"
        }
    }

    static func tabs(for area: Area) -> [ShellTab] {
        area == .med ? [.home, .consult, .shifts, .account] : [.home, .appointments, .results, .account]
    }
}

// MARK: - Raíz del shell (iOS / MED / … e iOS / PAC / …)

struct ShellRoot: View {
    let user: UserProfile
    @State private var area: Area
    @State private var tab: ShellTab = .home

    private var areaKey: String { "climesa.area.\(user.id.uuidString)" }

    init(user: UserProfile) {
        self.user = user
        let saved = UserDefaults.standard.string(forKey: "climesa.area.\(user.id.uuidString)")
        _area = State(initialValue: user.areas.first { $0.rawValue == saved } ?? user.areas.first ?? .med)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("climesa")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.background)

            TabView(selection: $tab) {
                ForEach(ShellTab.tabs(for: area), id: \.self) { t in
                    content(for: t)
                        .tabItem { Label(t.title(in: area), systemImage: t.icon) }
                        .tag(t)
                }
            }
            .tint(Theme.blue)
            .id(area)   // al cambiar de área se reconstruyen las pestañas
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onChange(of: area) { newArea in
            tab = .home
            UserDefaults.standard.set(newArea.rawValue, forKey: areaKey)
        }
    }

    @ViewBuilder
    private func content(for tab: ShellTab) -> some View {
        switch tab {
        case .home:
            ShellHomeView(user: user, area: area) { self.tab = $0 }
        case .consult:
            if FeatureFlags.clinicalModulesEnabled { ConsultationView(user: user) }
            else { ComingSoonView(label: "MEDICINA / CLIMESA", title: "Consultas.") }
        case .shifts:
            MyShiftsView(user: user)
        case .appointments:
            if FeatureFlags.clinicalModulesEnabled { ConsultationView(user: user) }
            else { ComingSoonView(label: "PACIENTE / CLIMESA", title: "Citas.") }
        case .results:
            if FeatureFlags.clinicalModulesEnabled { LabView(user: user) }
            else { ComingSoonView(label: "PACIENTE / CLIMESA", title: "Resultados.") }
        case .account:
            AccountView(user: user, area: $area)
        }
    }
}

// MARK: - Inicio · "Tu jornada."

struct ShellHomeView: View {
    let user: UserProfile
    let area: Area
    let navigate: (ShellTab) -> Void

    private var links: [ShellTab] {
        area == .med ? [.consult, .shifts, .account] : [.appointments, .results, .account]
    }

    var body: some View {
        ScreenScaffold(label: "\(area.title.uppercased()) / CLIMESA", title: "Tu jornada.", titleSize: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Text(user.name)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(.white)
                Text("\(area.title) · Cuenta activa")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.blue)

            VStack(spacing: 0) {
                ForEach(links, id: \.self) { link in
                    Button { navigate(link) } label: {
                        HStack {
                            Text(link.title(in: area)).font(.system(size: 12.5)).foregroundColor(Theme.blue)
                            Spacer()
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.blue)
                        }
                        .padding(.vertical, 28)
                        .contentShape(Rectangle())
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Módulo pendiente · "Este módulo todavía no está habilitado."

struct ComingSoonView: View {
    let label: String
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel(text: label).padding(.top, 24)
                HeadlineText(text: title, size: 30).padding(.top, 14)
                Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 22)
                MonoLabel(text: "PRÓXIMA ENTREGA").padding(.top, 20)
                Text("Este módulo todavía no está habilitado.")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.4)
                    .lineSpacing(4)
                    .foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                BodyText(text: "Su acceso y navegación ya están definidos para tu rol. Las operaciones se habilitarán en la siguiente entrega.")
                    .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }
}

// MARK: - Mis turnos (cargando · con datos · vacío · error)

@MainActor
final class MyShiftsViewModel: ObservableObject {
    enum Phase { case loading, loaded([ShiftOccurrence]), failed }

    let user: UserProfile
    private let backend = HospitalBackend.shared
    @Published var phase: Phase = .loading

    init(user: UserProfile) { self.user = user }

    func load(showSpinner: Bool = true) async {
        if showSpinner { phase = .loading }
        do {
            phase = .loaded(try await backend.myShifts(for: user))
        } catch {
            phase = .failed
        }
    }
}

struct MyShiftsView: View {
    @StateObject private var vm: MyShiftsViewModel

    init(user: UserProfile) { _vm = StateObject(wrappedValue: MyShiftsViewModel(user: user)) }

    var body: some View {
        Group {
            switch vm.phase {
            case .loading:
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "lock").font(.system(size: 28)).foregroundColor(Theme.blue)
                    Text("Consultando tus turnos…").font(.system(size: 11)).foregroundColor(Theme.muted)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 150)
                .frame(maxWidth: .infinity, alignment: .leading)

            case .failed:
                VStack(alignment: .leading, spacing: 16) {
                    Banner(kind: .error, text: "No se pudo cargar la información. Revisa tu conexión e inténtalo de nuevo.")
                    PrimaryButton(title: "Volver a intentar") { Task { await vm.load() } }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

            case .loaded(let items):
                ScreenScaffold(label: "MEDICINA / CLIMESA", title: "Mis turnos.", titleSize: 30,
                               refresh: { await vm.load(showSpinner: false) }) {
                    if items.isEmpty {
                        Text("No tienes turnos publicados.")
                            .font(.system(size: 13)).foregroundColor(Theme.muted)
                    }
                    ForEach(items) { shift in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(shift.service)
                                .font(.system(size: 17, weight: .semibold)).tracking(-0.3).foregroundColor(Theme.ink)
                            Text(shift.startText).font(.system(size: 12.5)).foregroundColor(Theme.ink)
                            Text(shift.endText).font(.system(size: 12.5)).foregroundColor(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if shift.published {
                                HStack(spacing: 5) {
                                    Circle().fill(Theme.blue).frame(width: 4, height: 4)
                                    Text("Publicado").font(.system(size: 8.5)).foregroundColor(Theme.blue)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color(hex: 0xE8EBFB))
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .task { await vm.load() }
    }
}

// MARK: - Mi cuenta (+ selector Medicina / Paciente)

struct AccountView: View {
    let user: UserProfile
    @Binding var area: Area
    @EnvironmentObject var auth: AuthViewModel
    @State private var isRefreshing = false
    @State private var notice: (text: String, isError: Bool)?
    @AppStorage(HospitalBackend.offlineKey) private var simulateOffline = false

    var body: some View {
        ScreenScaffold(label: "\(area.title.uppercased()) / CLIMESA", title: "Mi cuenta.", titleSize: 30) {
            if let notice {
                Banner(kind: notice.isError ? .error : .info, text: notice.text)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(user.name)
                    .font(.system(size: 18, weight: .semibold)).tracking(-0.3).foregroundColor(Theme.ink)
                Text(user.email)
                    .font(.system(size: 13)).foregroundColor(Theme.ink).padding(.top, 14)
                Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 16)
                Text("Roles: " + user.areas.map(\.code).joined(separator: ", "))
                    .font(.system(size: 9.5, design: .monospaced)).foregroundColor(Theme.ink).padding(.top, 16)
                Text("Tu cuenta es personal. Cierra sesión al terminar.")
                    .font(.system(size: 10.5)).foregroundColor(Theme.muted).padding(.top, 14)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)

            if user.areas.count > 1 {
                HStack(spacing: 6) {
                    ForEach(user.areas) { a in
                        Button { area = a } label: {
                            Text(a.title)
                                .font(.system(size: 10.5, weight: a == area ? .semibold : .regular))
                                .foregroundColor(Theme.blue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Theme.card)
                                .overlay(Rectangle().stroke(a == area ? Theme.blue : Theme.line, lineWidth: 1))
                        }
                    }
                }
                .padding(8)
                .background(Color(hex: 0xEFEDE8))
            }

            Button {
                Task {
                    isRefreshing = true
                    let ok = await auth.refreshAccess()
                    isRefreshing = false
                    notice = ok ? ("Acceso actualizado.", false)
                                : ("No se pudo actualizar el acceso. Revisa tu conexión e inténtalo de nuevo.", true)
                }
            } label: {
                Text(isRefreshing ? "Actualizando…" : "Actualizar acceso")
                    .font(.system(size: 12.5)).foregroundColor(Theme.blue)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
            }
            .disabled(isRefreshing)
            .padding(.top, 6)

            LinkButton(title: "Cerrar sesión") { auth.logout() }
                .padding(.top, 18)

            #if DEBUG
            Toggle("Simular sin conexión (solo depuración)", isOn: $simulateOffline)
                .font(.system(size: 11)).foregroundColor(Theme.muted)
                .tint(Theme.blue)
                .padding(.top, 24)
            #endif
        }
    }
}
