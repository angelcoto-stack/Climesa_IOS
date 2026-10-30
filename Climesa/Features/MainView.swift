import SwiftUI

struct MainView: View {
    let user: UserProfile

    enum Tab: Hashable { case home, consult, labs, rooms, ambulance, shifts }
    @State private var tab: Tab = .home

    private var tabs: [Tab] {
        switch user.role {
        case .administrador: return [.home, .rooms, .ambulance, .shifts, .labs]
        case .doctor: return [.home, .consult, .labs, .shifts, .ambulance]
        case .recepcionista: return [.home, .rooms, .ambulance, .shifts]
        case .asistente: return [.home, .rooms, .labs, .ambulance, .shifts]
        case .paciente: return [.home, .consult, .labs, .rooms, .ambulance]
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(tabs, id: \.self) { t in
                content(for: t)
                    .tabItem { Label(title(for: t), systemImage: icon(for: t)) }
                    .tag(t)
            }
        }
        .tint(Theme.blue)
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        switch tab {
        case .home: HomeView(user: user)
        case .consult: ConsultationView(user: user)
        case .labs: LabView(user: user)
        case .rooms: RoomsView(user: user)
        case .ambulance: AmbulanceView(user: user)
        case .shifts: ShiftsView(user: user)
        }
    }

    private func title(for tab: Tab) -> String {
        switch tab {
        case .home: return "Inicio"
        case .consult: return user.role == .paciente ? "Historial" : "Consulta"
        case .labs: return "Laboratorio"
        case .rooms: return user.role == .paciente ? "Habitación" : "Habitaciones"
        case .ambulance: return "Ambulancia"
        case .shifts: return "Turnos"
        }
    }

    private func icon(for tab: Tab) -> String {
        switch tab {
        case .home: return "house"
        case .consult: return "stethoscope"
        case .labs: return "doc.text.magnifyingglass"
        case .rooms: return "bed.double"
        case .ambulance: return "cross.case"
        case .shifts: return "calendar"
        }
    }
}

// MARK: - Inicio (información pública + accesos del rol)

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var overview: PublicOverview?
    func load() async { overview = await HospitalBackend.shared.publicOverview() }
}

struct HomeView: View {
    let user: UserProfile
    @StateObject private var vm = HomeViewModel()

    private var roleSummary: String {
        switch user.role {
        case .administrador: return "Gestiona usuarios, habitaciones, turnos, recursos y la ambulancia."
        case .doctor: return "Registra consultas, emite órdenes de laboratorio y revisa expedientes."
        case .recepcionista: return "Asigna camas, controla turnos y despacha la ambulancia."
        case .asistente: return "Apoya el ingreso de pacientes y actualiza el estado de laboratorio."
        case .paciente: return "Consulta tu historial, resultados y solicita atención."
        }
    }

    var body: some View {
        ScreenScaffold(label: "\(user.role.title.uppercased()) / 01",
                       title: "Hola, \(user.firstName).",
                       subtitle: roleSummary,
                       refresh: { await vm.load() }) {
            if let o = vm.overview {
                SectionTitle(text: "Estado del hospital · público")
                Card {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(o.occupiedBeds)")
                            .font(.system(size: 40, weight: .bold)).tracking(-1.5).foregroundColor(Theme.ink)
                        Text("de \(o.totalBeds) camas ocupadas")
                            .font(.system(size: 13)).foregroundColor(Theme.muted)
                    }
                    ProgressBar(value: Double(o.occupiedBeds), total: Double(max(o.totalBeds, 1)))
                    HStack {
                        Pill(text: "\(o.vipFree) VIP libres", fg: Theme.ink, bg: Theme.infoBg)
                        Pill(text: "\(o.semiBedsFree) camas semiprivadas libres", fg: Theme.ink, bg: Theme.infoBg)
                    }
                }

                SectionTitle(text: "Médicos de turno ahora")
                Card {
                    if o.onDutyDoctors.isEmpty {
                        Text("Sin médicos registrados en este momento.")
                            .font(.system(size: 13)).foregroundColor(Theme.muted)
                    } else {
                        ForEach(o.onDutyDoctors, id: \.self) { name in
                            HStack(spacing: 10) {
                                Circle().fill(Theme.blue).frame(width: 7, height: 7)
                                Text(name).font(.system(size: 14)).foregroundColor(Theme.ink)
                            }
                        }
                    }
                }

                SectionTitle(text: "Avisos generales")
                ForEach(o.notices, id: \.self) { Banner(kind: .info, text: $0) }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .task { await vm.load() }
    }
}

struct ProgressBar: View {
    let value: Double
    let total: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.line)
                Rectangle().fill(Theme.blue).frame(width: geo.size.width * CGFloat(min(value / total, 1)))
            }
        }
        .frame(height: 6)
    }
}
