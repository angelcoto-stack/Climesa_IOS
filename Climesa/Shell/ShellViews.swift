import SwiftUI

extension AppTab {
    /// Título visible de la pestaña (clave `tab.*` de Localizable.xcstrings).
    var title: String { L.text(titleKey) }
}

// MARK: - Raíz del shell (iOS / MED / … e iOS / PAC / …)

/// Pestañas por rol y permisos (`TabPolicy`), banda de conexión en vivo y tiempo real sin sondeo.
struct ShellRoot: View {
    let user: UserProfile
    @EnvironmentObject var auth: AuthViewModel
    @State private var area: Area
    @State private var tab: AppTab
    @StateObject private var live = LiveViewModel()
    @StateObject private var shifts: MyShiftsViewModel

    private var areaKey: String { "climesa.area.\(user.id)" }

    init(user: UserProfile, services: ClientServices?) {
        self.user = user
        let saved = UserDefaults.standard.string(forKey: "climesa.area.\(user.id)")
        let initial = user.areas.first { $0.rawValue == saved } ?? user.areas.first ?? .med
        _area = State(initialValue: initial)
        _tab = State(initialValue: ShellRoot.tabs(for: user, area: initial).first ?? .perfil)
        _shifts = StateObject(wrappedValue: MyShiftsViewModel(api: services?.api))
    }

    /// Pestañas del rol elegido, ya filtradas por los permisos del perfil verificado.
    private static func tabs(for user: UserProfile, area: Area) -> [AppTab] {
        if case let .tabs(_, tabs) = TabPolicy.decide(user.access, preferredRole: area.rawValue) { return tabs }
        return []
    }

    private var tabs: [AppTab] { ShellRoot.tabs(for: user, area: area) }

    var body: some View {
        VStack(spacing: 0) {
            Text("climesa")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.background)

            ConnectionBanner(state: live.snapshot.connection)

            TabView(selection: $tab) {
                ForEach(tabs, id: \.self) { t in
                    content(for: t)
                        .tabItem { Label(t.title, systemImage: t.symbol) }
                        .tag(t)
                }
            }
            .tint(Theme.blue)
            .id(area)   // al cambiar de área se reconstruyen las pestañas
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onChange(of: area) { newArea in
            tab = ShellRoot.tabs(for: user, area: newArea).first ?? .perfil
            UserDefaults.standard.set(newArea.rawValue, forKey: areaKey)
        }
        .onChange(of: tabs) { newTabs in
            // Un cambio de permisos puede quitar la pestaña abierta.
            if !newTabs.contains(tab) { tab = newTabs.first ?? .perfil }
        }
        .onChange(of: user.areas) { newAreas in
            if !newAreas.contains(area), let first = newAreas.first { area = first }
        }
        // Tiempo real: se suscribe al entrar y la conexión se cierra al cancelar la tarea. No hay temporizadores de datos.
        .task(id: user.channels) {
            let service = await auth.makeRealtime()
            await live.run(service: service, channels: user.channels)
        }
        // Un evento de cuentas (roles o permisos) obliga a verificar de nuevo el perfil.
        .onChange(of: live.snapshot.profileVersion) { _ in
            Task { _ = await auth.refreshAccess() }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .miDia, .inicio:
            ShellHomeView(user: user, area: area, tabs: tabs) { self.tab = $0 }
        case .turnos:
            MyShiftsView(model: shifts, shiftsVersion: live.snapshot.shiftsVersion)
        case .perfil, .mas:
            AccountView(user: user, area: $area)
        default:
            ComingSoonView(label: "\(area.title.uppercased()) / CLIMESA", title: tab.title + ".")
        }
    }
}

// MARK: - Conexión en vivo

/// Aviso visible solo cuando el tiempo real no está conectado.
struct ConnectionBanner: View {
    let state: ConnectionState

    var body: some View {
        if state != .live {
            Text(L.text(state == .offline ? "live.offline" : "live.reconnecting"))
                .font(.system(size: 11.5))
                .foregroundColor(state == .offline ? Theme.errorText : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(state == .offline ? Theme.errorBg : Theme.infoBg)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// MARK: - Inicio · "Tu jornada."

struct ShellHomeView: View {
    let user: UserProfile
    let area: Area
    let tabs: [AppTab]
    let navigate: (AppTab) -> Void

    private var links: [AppTab] {
        let wanted: [AppTab] = area == .med ? [.pacientes, .turnos, .perfil] : [.citas, .examenes, .mas]
        return wanted.filter { tabs.contains($0) }
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
                            Text(link.title).font(.system(size: 12.5)).foregroundColor(Theme.blue)
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

/// Lee GET /turnos/mios. Se vuelve a pedir solo al entrar y cuando llega un evento de turnos (sin sondeo).
@MainActor
final class MyShiftsViewModel: ObservableObject {
    enum Phase { case loading, loaded([ShiftOccurrence]), failed }

    private let api: APIClient?
    @Published var phase: Phase = .loading

    init(api: APIClient?) { self.api = api }

    var hasLoaded: Bool {
        if case .loaded = phase { return true }
        return false
    }

    /// Primera carga con indicador; las siguientes (por eventos) refrescan sin borrar lo que ya se ve.
    func reload() async { await load(showSpinner: !hasLoaded) }

    func load(showSpinner: Bool = true) async {
        guard let api else {
            phase = .failed
            return
        }
        if showSpinner { phase = .loading }
        do {
            let rows = try await api.get("/turnos/mios", as: [TurnoAPI].self)
            phase = .loaded(rows.map { ShiftOccurrence($0) })
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // Si ya había datos se conservan; el error solo se muestra cuando no hay nada que enseñar.
            if !hasLoaded { phase = .failed }
        }
    }
}

struct MyShiftsView: View {
    @ObservedObject var model: MyShiftsViewModel
    let shiftsVersion: Int

    var body: some View {
        Group {
            switch model.phase {
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
                    PrimaryButton(title: "Volver a intentar") { Task { await model.load() } }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

            case .loaded(let items):
                ScreenScaffold(label: "MEDICINA / CLIMESA", title: "Mis turnos.", titleSize: 30,
                               refresh: { await model.load(showSpinner: false) }) {
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
        // Al entrar y cada vez que un evento de turnos (o una reconexión) sube el contador.
        .task(id: shiftsVersion) { await model.reload() }
    }
}

// MARK: - Mi cuenta (+ selector Medicina / Paciente)

struct AccountView: View {
    let user: UserProfile
    @Binding var area: Area
    @EnvironmentObject var auth: AuthViewModel
    @State private var isRefreshing = false
    @State private var notice: (text: String, isError: Bool)?

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
                Text("Roles: " + user.roles.joined(separator: ", "))
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
        }
    }
}
