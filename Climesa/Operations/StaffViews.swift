import SwiftUI

// MARK: - Directorio de personal (GET /personal) y ficha

struct StaffDirectoryView: View {
    let user: UserProfile
    let api: APIClient?
    let liveVersion: Int
    @StateObject private var resource: RemoteResource<[StaffMember]>
    @State private var query = ""
    @State private var scope: StaffScope = .activos
    @State private var creating = false

    init(user: UserProfile, api: APIClient?, liveVersion: Int) {
        self.user = user
        self.api = api
        self.liveVersion = liveVersion
        _resource = StateObject(wrappedValue: RemoteResource<[StaffMember]>(api: api, path: "/personal"))
    }

    var body: some View {
        ResourceContent(resource: resource, loadingText: "Consultando el personal…") { people in
            ScreenScaffold(label: "ADMINISTRACIÓN / CLIMESA", title: "Personal.", titleSize: 30,
                           refresh: { await resource.load(showSpinner: false) }) {
                if StaffWriteRules.canManage(user.access) {
                    SecondaryButton(title: "Registrar personal") { creating = true }
                }
                PlainField(label: "Buscar en el directorio", text: $query, prompt: "Nombre o especialidad")
                Picker("Mostrar", selection: $scope) {
                    ForEach(StaffScope.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.blue)
                staffList(people)
            }
        }
        // Al entrar y cada vez que un evento en vivo sube el contador.
        .task(id: liveVersion) { await resource.reload() }
        .sheet(isPresented: $creating) {
            StaffFormSheet(mode: .create, user: user, api: api) {
                Task { await resource.load(showSpinner: false) }
            }
        }
    }

    @ViewBuilder
    private func staffList(_ people: [StaffMember]) -> some View {
        let rows = StaffDirectory.filter(people, query: query, scope: scope)
        if rows.isEmpty {
            Text("No hay personas en esta vista.").font(.system(size: 13)).foregroundColor(Theme.muted)
        }
        ForEach(rows) { person in
            NavigationLink {
                StaffDetailView(person: person, user: user, api: api, liveVersion: liveVersion) {
                    Task { await resource.load(showSpinner: false) }
                }
            } label: {
                StaffRow(person: person)
            }
            .buttonStyle(.plain)
        }
    }
}

struct StaffRow: View {
    let person: StaffMember

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(person.fullName)
                .font(.system(size: 15, weight: .semibold)).tracking(-0.2).foregroundColor(Theme.ink)
            Text(StaffLabels.function(person.type)).font(.system(size: 12.5)).foregroundColor(Theme.ink)
            if let specialty = person.specialty, !specialty.isEmpty {
                Text(specialty).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            HStack(spacing: 6) {
                Pill(text: person.isActive ? "Activo" : "Inactivo",
                     fg: person.isActive ? Theme.ink : Theme.errorText,
                     bg: person.isActive ? Theme.infoBg : Theme.errorBg)
                if let area = person.area, !area.isEmpty {
                    Pill(text: area)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// Ficha de una persona: función en español, área, estado, inscripciones y, con `turnos.ver`, sus próximos turnos.
struct StaffDetailView: View {
    let person: StaffMember
    let user: UserProfile
    let api: APIClient?
    let liveVersion: Int
    /// Avisa a la lista que el registro cambió para que vuelva a pedir el directorio.
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var changingState = false

    init(person: StaffMember, user: UserProfile, api: APIClient?, liveVersion: Int, onChanged: @escaping () -> Void) {
        self.person = person
        self.user = user
        self.api = api
        self.liveVersion = liveVersion
        self.onChanged = onChanged
    }

    var body: some View {
        ScreenScaffold(label: "PERSONAL / CLIMESA", title: person.fullName, titleSize: 26) {
            Card {
                DetailRow(label: "Función", value: StaffLabels.function(person.type))
                DetailRow(label: "Especialidad", value: valueOrDash(person.specialty, empty: "Sin especialidad registrada"))
                DetailRow(label: "Área", value: valueOrDash(person.area, empty: "Sin asignar"))
                DetailRow(label: "Estado", value: person.isActive ? "Activo" : "Inactivo")
            }

            if StaffWriteRules.canManage(user.access) {
                SecondaryButton(title: "Editar datos") { editing = true }
                LinkButton(title: person.isActive ? "Inactivar" : "Reactivar") { changingState = true }
            }

            SectionTitle(text: "Inscripciones profesionales")
            registrations

            if user.access.hasPermission(OperationPermission.viewShifts) {
                SectionTitle(text: "Turnos próximos")
                UpcomingShiftsSection(staffId: person.id, api: api, liveVersion: liveVersion)
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $editing) {
            StaffFormSheet(mode: .edit(person), user: user, api: api) {
                onChanged()
                dismiss()
            }
        }
        .sheet(isPresented: $changingState) {
            StaffFormSheet(mode: .activeChange(person), user: user, api: api) {
                onChanged()
                dismiss()
            }
        }
    }

    private func valueOrDash(_ value: String?, empty: String) -> String {
        guard let value, !value.isEmpty else { return empty }
        return value
    }

    @ViewBuilder
    private var registrations: some View {
        let items = person.registrations ?? []
        if items.isEmpty {
            Text("Sin inscripciones registradas.").font(.system(size: 13)).foregroundColor(Theme.muted)
        } else {
            ForEach(items, id: \.rowKey) { item in
                Card {
                    Text("\(item.board ?? "Inscripción") · \(item.number ?? "sin número")")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.ink)
                    Text("Vigencia: " + StaffDirectory.vigency(item))
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
        }
    }
}

// MARK: - Alta, edición e inactivación de personal (POST /personal, PATCH /personal/{id})

/// Alta, corrección con versión y motivo, o inactivar/reactivar (mismo PATCH con `active`).
struct StaffFormSheet: View {
    enum Mode {
        case create
        case edit(StaffMember)
        case activeChange(StaffMember)
    }

    let mode: Mode
    let user: UserProfile
    let api: APIClient?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var action = ActionModel()
    @State private var draft: StaffDraft
    @State private var reason = ""

    init(mode: Mode, user: UserProfile, api: APIClient?, onSaved: @escaping () -> Void) {
        self.mode = mode
        self.user = user
        self.api = api
        self.onSaved = onSaved
        switch mode {
        case .create:
            _draft = State(initialValue: StaffDraft())
        case .edit(let member), .activeChange(let member):
            _draft = State(initialValue: StaffDraft(member: member))
        }
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var activeChangeMember: StaffMember? {
        if case .activeChange(let member) = mode { return member }
        return nil
    }

    private var title: String {
        switch mode {
        case .create: return "Registrar personal"
        case .edit: return "Editar personal"
        case .activeChange(let member): return member.isActive ? "Inactivar personal" : "Reactivar personal"
        }
    }

    private var submitTitle: String {
        switch mode {
        case .create: return "Registrar"
        case .edit: return "Guardar cambios"
        case .activeChange(let member): return member.isActive ? "Inactivar" : "Reactivar"
        }
    }

    /// DUI y teléfono solo con `personal.ver_datos_personales`; sin él no se muestran ni se envían.
    private var showsPersonalData: Bool { StaffWriteRules.canSeePersonalData(user.access) }

    var body: some View {
        SheetScaffold(title: title) {
            if action.conflict {
                Banner(kind: .error, text: "El registro cambió. Cierra y vuelve a abrirlo para ver sus datos actuales; el cambio no se guardó.")
                SecondaryButton(title: "Cerrar") {
                    onSaved()
                    dismiss()
                }
            } else {
                if let message = action.error {
                    Banner(kind: .error, text: message)
                }
                if let member = activeChangeMember {
                    BodyText(text: member.isActive
                             ? "\(member.fullName) saldrá del directorio activo. El registro se conserva con tu motivo."
                             : "\(member.fullName) volverá al directorio activo. Tu motivo queda en el historial.")
                } else {
                    PlainField(label: "Nombres", text: $draft.givenNames, prompt: "Nombres")
                    PlainField(label: "Apellidos", text: $draft.surnames, prompt: "Apellidos")
                    Picker("Función", selection: $draft.type) {
                        Text("Elige una función").tag("")
                        ForEach(StaffLabels.functionCodes, id: \.self) { code in
                            Text(StaffLabels.function(code)).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.blue)
                    PlainField(label: "Especialidad (opcional)", text: $draft.specialty, prompt: "Especialidad")
                    if showsPersonalData {
                        PlainField(label: "DUI (opcional)", text: $draft.dui, prompt: "00000000-0")
                        PlainField(label: "Teléfono (opcional)", text: $draft.phone, prompt: "8 dígitos")
                        BodyText(text: "Si dejas el DUI o el teléfono en blanco, no se cambian.")
                    }
                }
                if !isCreate {
                    PlainField(label: "Motivo", text: $reason, prompt: "Al menos 10 caracteres", axis: .vertical)
                }
                PrimaryButton(title: action.busy ? "Guardando…" : submitTitle, isEnabled: !action.busy) { submit() }
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
        switch mode {
        case .create:
            switch StaffWriteRules.prepareCreate(draft, profile: user.access) {
            case .failure(let problem):
                action.fail(problem.message)
            case .success(let request):
                Task {
                    let saved = await action.run({ try await api.post("/personal", body: request) })
                    if saved {
                        onSaved()
                        dismiss()
                    }
                }
            }
        case .edit(let member):
            switch StaffWriteRules.prepareUpdate(draft, current: member, reason: reason, profile: user.access) {
            case .failure(let problem):
                action.fail(problem.message)
            case .success(let request):
                let path = "/personal/\(member.id)"
                Task {
                    let saved = await action.run({ try await api.patch(path, body: request) })
                    if saved {
                        onSaved()
                        dismiss()
                    }
                }
            }
        case .activeChange(let member):
            switch StaffWriteRules.prepareActiveChange(member, active: !member.isActive, reason: reason, profile: user.access) {
            case .failure(let problem):
                action.fail(problem.message)
            case .success(let request):
                let path = "/personal/\(member.id)"
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
}

/// Próximos turnos de la persona, tomados de GET /turnos (solo si el perfil tiene `turnos.ver`).
struct UpcomingShiftsSection: View {
    let staffId: String
    let liveVersion: Int
    @StateObject private var resource: RemoteResource<[PlannedShift]>

    init(staffId: String, api: APIClient?, liveVersion: Int) {
        self.staffId = staffId
        self.liveVersion = liveVersion
        _resource = StateObject(wrappedValue: RemoteResource<[PlannedShift]>(api: api, path: "/turnos"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch resource.phase {
            case .loading:
                Text("Consultando los turnos…").font(.system(size: 12)).foregroundColor(Theme.muted)
            case .failed:
                Text("No se pudieron cargar los turnos.").font(.system(size: 12)).foregroundColor(Theme.errorText)
            case .loaded(let rows):
                let upcoming = ShiftRules.upcoming(rows, staffId: staffId, now: Date())
                if upcoming.isEmpty {
                    Text("Sin turnos próximos.").font(.system(size: 13)).foregroundColor(Theme.muted)
                }
                ForEach(upcoming) { shift in
                    Card {
                        Text(OperationsDates.text(shift.start)).font(.system(size: 13)).foregroundColor(Theme.ink)
                        Text("Hasta " + OperationsDates.text(shift.end)).font(.system(size: 12)).foregroundColor(Theme.muted)
                        Text((shift.area ?? "Sin área") + " · " + StaffLabels.shiftState(shift.state))
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
            }
        }
        .task(id: liveVersion) { await resource.reload() }
    }
}
