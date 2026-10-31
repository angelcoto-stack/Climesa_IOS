import SwiftUI

// MARK: - Planificación de turnos: listar (GET /turnos), publicar (POST /turnos/publicar) y cancelar (PATCH /turnos/{id})

struct ShiftPlanningView: View {
    let user: UserProfile
    let api: APIClient?
    let liveVersion: Int
    @StateObject private var resource: RemoteResource<[PlannedShift]>
    @State private var filter: ShiftFilter = .todos
    @State private var publishing = false
    @State private var cancelling: PlannedShift?
    @State private var notice: PublishResult?

    init(user: UserProfile, api: APIClient?, liveVersion: Int) {
        self.user = user
        self.api = api
        self.liveVersion = liveVersion
        _resource = StateObject(wrappedValue: RemoteResource<[PlannedShift]>(api: api, path: "/turnos"))
    }

    var body: some View {
        ResourceContent(resource: resource, loadingText: "Consultando los turnos…") { shifts in
            ScreenScaffold(label: "OPERACIONES / CLIMESA", title: "Turnos.", titleSize: 30,
                           refresh: { await resource.load(showSpinner: false) }) {
                if let notice {
                    PublishNoticeView(result: notice) { self.notice = nil }
                }
                if ShiftRules.canPublish(user.access) {
                    SecondaryButton(title: "Publicar planificación") { publishing = true }
                }
                filterPicker
                shiftList(shifts)
            }
        }
        // Al entrar y cada vez que un evento en vivo sube el contador.
        .task(id: liveVersion) { await resource.reload() }
        .sheet(isPresented: $publishing) {
            PublishSheet(user: user, api: api, areas: ShiftRules.areaOptions(resource.value ?? [])) { result in
                notice = result
                Task { await resource.load(showSpinner: false) }
            }
        }
        .sheet(item: $cancelling) { shift in
            CancelShiftSheet(shift: shift, user: user, api: api) {
                Task { await resource.load(showSpinner: false) }
            }
        }
    }

    private var filterPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Estado del turno")
            Picker("Estado del turno", selection: $filter) {
                ForEach(ShiftFilter.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.blue)
        }
    }

    @ViewBuilder
    private func shiftList(_ shifts: [PlannedShift]) -> some View {
        let rows = filter.apply(shifts)
        if rows.isEmpty {
            Text("Sin turnos en esta vista.").font(.system(size: 13)).foregroundColor(Theme.muted)
        }
        ForEach(rows) { shift in
            ShiftCard(shift: shift, canCancel: ShiftRules.canCancel(shift, profile: user.access)) {
                cancelling = shift
            }
        }
    }
}

struct ShiftCard: View {
    let shift: PlannedShift
    let canCancel: Bool
    let onCancel: () -> Void

    var body: some View {
        Card {
            Text(shift.person ?? "Sin nombre")
                .font(.system(size: 17, weight: .semibold)).tracking(-0.3).foregroundColor(Theme.ink)
            Text(shift.area ?? "Sin área").font(.system(size: 12.5)).foregroundColor(Theme.muted)
            Text(OperationsDates.text(shift.start)).font(.system(size: 12.5)).foregroundColor(Theme.ink)
            Text("Hasta " + OperationsDates.text(shift.end)).font(.system(size: 12.5)).foregroundColor(Theme.ink)
            HStack(spacing: 6) {
                Pill(text: StaffLabels.shiftState(shift.state),
                     fg: shift.state == "cancelado" ? Theme.errorText : Theme.ink,
                     bg: shift.state == "cancelado" ? Theme.errorBg : Theme.infoBg)
                if let type = shift.type {
                    Pill(text: StaffLabels.shiftType(type))
                }
            }
            if canCancel {
                LinkButton(title: "Cancelar turno", action: onCancel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Resultado de publicar: se publica aunque queden huecos de cobertura y se muestran para que se decida.
struct PublishNoticeView: View {
    let result: PublishResult
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Banner(kind: .info, text: PublishRules.summary(result))
            ForEach(Array(result.warnings.enumerated()), id: \.offset) { entry in
                Text(PublishRules.gapText(entry.element))
                    .font(.system(size: 11.5)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LinkButton(title: "Entendido", action: onClose)
        }
    }
}

/// Publica los borradores de un rango (máximo 31 días) y, si se elige, de una sola área.
struct PublishSheet: View {
    let user: UserProfile
    let api: APIClient?
    let areas: [AreaOption]
    let onPublished: (PublishResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var action = ActionModel()
    @State private var from = Date()
    @State private var to = Date()
    @State private var areaId = ""

    var body: some View {
        SheetScaffold(title: "Publicar planificación") {
            if let message = action.error {
                Banner(kind: .error, text: message)
            }
            BodyText(text: "Se publican los turnos en borrador del rango (máximo 31 días). Si quedan huecos de cobertura se publica igual y se te avisa.")
            DatePicker("Desde", selection: $from, displayedComponents: .date)
                .tint(Theme.blue)
            DatePicker("Hasta", selection: $to, in: from..., displayedComponents: .date)
                .tint(Theme.blue)
            if !areas.isEmpty {
                Picker("Área", selection: $areaId) {
                    Text("Todas las áreas").tag("")
                    ForEach(areas) { area in
                        Text(area.name).tag(area.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.blue)
            }
            PrimaryButton(title: action.busy ? "Publicando…" : "Publicar turnos", isEnabled: !action.busy) { submit() }
        }
    }

    private func submit() {
        guard let api else {
            action.fail("Falta configurar el servidor de Climesa.")
            return
        }
        let prepared = PublishRules.prepare(from: PublishRules.dayString(from), to: PublishRules.dayString(to),
                                            areaId: areaId, profile: user.access)
        switch prepared {
        case .failure(let problem):
            action.fail(problem.message)
        case .success(let request):
            Task {
                var published: PublishResult?
                let saved = await action.run({
                    published = try await api.post("/turnos/publicar", body: request, as: PublishResult.self)
                })
                if saved, let published {
                    onPublished(published)
                    dismiss()
                }
            }
        }
    }
}

/// Cancela un turno con motivo; la API exige la versión que se vio al abrir la hoja.
struct CancelShiftSheet: View {
    let shift: PlannedShift
    let user: UserProfile
    let api: APIClient?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var action = ActionModel()
    @State private var reason = ""

    var body: some View {
        SheetScaffold(title: "Cancelar turno") {
            if action.conflict {
                Banner(kind: .error, text: "El turno cambió. Cierra y vuelve a abrirlo para ver su estado actual; la cancelación no se guardó.")
                SecondaryButton(title: "Cerrar") {
                    onSaved()
                    dismiss()
                }
            } else {
                if let message = action.error {
                    Banner(kind: .error, text: message)
                }
                BodyText(text: "Se cancelará el turno de \(shift.person ?? "la persona") en \(shift.area ?? "el área"), del \(OperationsDates.text(shift.start)) al \(OperationsDates.text(shift.end)). El registro se conserva con tu motivo.")
                PlainField(label: "Motivo de la cancelación", text: $reason, prompt: "Al menos 10 caracteres", axis: .vertical)
                PrimaryButton(title: action.busy ? "Cancelando…" : "Cancelar turno", isEnabled: !action.busy, tint: Theme.errorText) { submit() }
                SecondaryButton(title: "Volver", isEnabled: !action.busy) { dismiss() }
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
        switch ShiftRules.prepareCancel(shift, profile: user.access, reason: reason) {
        case .failure(let problem):
            action.fail(problem.message)
        case .success(let request):
            let path = "/turnos/\(shift.id)"
            Task {
                let saved = await action.run({ try await api.patch(path, body: request) })
                if saved {
                    onSaved()
                    dismiss()
                }
            }
        }
    }
}
