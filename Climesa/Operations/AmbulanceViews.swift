import SwiftUI

// MARK: - Estado de la ambulancia (GET /ambulancia) y mantenimiento (POST /ambulancia/mantenimiento)

struct AmbulanceView: View {
    let user: UserProfile
    let api: APIClient?
    let liveVersion: Int
    @StateObject private var resource: RemoteResource<AmbulanceStatus>
    /// Estado que se vio al abrir la hoja: la versión que se envía es la de esa pantalla, no una posterior.
    @State private var pending: AmbulanceStatus?

    init(user: UserProfile, api: APIClient?, liveVersion: Int) {
        self.user = user
        self.api = api
        self.liveVersion = liveVersion
        _resource = StateObject(wrappedValue: RemoteResource<AmbulanceStatus>(api: api, path: "/ambulancia"))
    }

    var body: some View {
        ResourceContent(resource: resource, loadingText: "Consultando la ambulancia…") { status in
            ScreenScaffold(label: "OPERACIONES / CLIMESA", title: "Ambulancia.", titleSize: 30,
                           refresh: { await resource.load(showSpinner: false) }) {
                statusCard(status)
                serviceSection(status)
                maintenanceSection(status)
            }
        }
        // Al entrar y cada vez que un evento en vivo sube el contador.
        .task(id: liveVersion) { await resource.reload() }
        .sheet(isPresented: Binding(get: { pending != nil }, set: { shown in if !shown { pending = nil } })) {
            if let status = pending {
                MaintenanceSheet(status: status, user: user, api: api) {
                    Task { await resource.load(showSpinner: false) }
                }
            }
        }
    }

    private func statusCard(_ status: AmbulanceStatus) -> some View {
        Card {
            Text(status.unit.plate)
                .font(.system(size: 17, weight: .semibold)).tracking(-0.3).foregroundColor(Theme.ink)
            Pill(text: StaffLabels.unitState(status.unit.state),
                 fg: status.unit.state == "en_mantenimiento" ? Theme.errorText : Theme.ink,
                 bg: status.unit.state == "en_mantenimiento" ? Theme.errorBg : Theme.infoBg)
            DetailRow(label: "Paramédico con turno en curso", value: status.hasParamedicOnDuty ? "Sí" : "No")
        }
    }

    @ViewBuilder
    private func serviceSection(_ status: AmbulanceStatus) -> some View {
        SectionTitle(text: "Servicio activo")
        if let service = status.activeService {
            Card {
                DetailRow(label: "Tipo", value: service.type.map { StaffLabels.serviceType($0) } ?? "No disponible")
                DetailRow(label: "Prioridad", value: service.priority.map { StaffLabels.priority($0) } ?? "No disponible")
                DetailRow(label: "Origen", value: service.origin ?? "No disponible")
                DetailRow(label: "Destino", value: service.destination ?? "No disponible")
                DetailRow(label: "Despachado", value: OperationsDates.text(service.dispatchedAt))
                DetailRow(label: "Tripulación", value: crewText(service.crew))
            }
        } else {
            Text("Sin servicio activo.").font(.system(size: 13)).foregroundColor(Theme.muted)
        }
    }

    private func crewText(_ crew: [CrewMember]?) -> String {
        guard let crew, !crew.isEmpty else { return "Sin tripulación registrada" }
        return crew.map { (member: CrewMember) -> String in
            let name = member.name ?? "Sin nombre"
            guard let role = member.role else { return name }
            return "\(name) (\(StaffLabels.crewRole(role)))"
        }.joined(separator: " · ")
    }

    /// Solo con el permiso del catálogo y sin servicio activo; sin ellos la pantalla es de solo lectura.
    @ViewBuilder
    private func maintenanceSection(_ status: AmbulanceStatus) -> some View {
        if MaintenanceRules.available(profile: user.access, unitState: status.unit.state) {
            let leaving = MaintenanceRules.isLeaving(unitState: status.unit.state)
            let blocked = MaintenanceRules.leavingBlocked(unitState: status.unit.state,
                                                          paramedicOnDuty: status.hasParamedicOnDuty)
            SectionTitle(text: "Mantenimiento")
            if blocked {
                BodyText(text: MaintenanceRules.blockedMessage)
            }
            PrimaryButton(title: leaving ? "Sacar de mantenimiento" : "Poner en mantenimiento",
                          isEnabled: !blocked) { pending = status }
        }
    }
}

/// Entrar o salir de mantenimiento con el motivo (10 a 500 caracteres).
struct MaintenanceSheet: View {
    let status: AmbulanceStatus
    let user: UserProfile
    let api: APIClient?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var action = ActionModel()
    @State private var reason = ""

    private var leaving: Bool { MaintenanceRules.isLeaving(unitState: status.unit.state) }
    private var title: String { leaving ? "Sacar de mantenimiento" : "Poner en mantenimiento" }

    var body: some View {
        SheetScaffold(title: title) {
            if action.conflict {
                Banner(kind: .error, text: "La unidad cambió. Cierra y vuelve a abrir para ver su estado actual; el cambio no se guardó.")
                SecondaryButton(title: "Cerrar") {
                    onSaved()
                    dismiss()
                }
            } else {
                if let message = action.error {
                    Banner(kind: .error, text: message)
                }
                BodyText(text: leaving ? "La unidad queda Disponible." : "La unidad no podrá despacharse mientras esté en mantenimiento.")
                PlainField(label: "Motivo", text: $reason, prompt: "Al menos 10 caracteres", axis: .vertical)
                PrimaryButton(title: action.busy ? "Guardando…" : title, isEnabled: !action.busy) { submit() }
            }
        }
        .onChange(of: reason) { newValue in
            let clamped = ReasonRules.clamp(newValue)
            if clamped != newValue { reason = clamped }
        }
    }

    private func submit() {
        guard let api else {
            action.fail("Falta configurar el servidor de Climesa.")
            return
        }
        switch MaintenanceRules.prepare(status: status, profile: user.access, reason: reason) {
        case .failure(let problem):
            action.fail(problem.message)
        case .success(let request):
            Task {
                let saved = await action.run({ try await api.post("/ambulancia/mantenimiento", body: request) })
                if saved {
                    onSaved()
                    dismiss()
                }
            }
        }
    }
}
