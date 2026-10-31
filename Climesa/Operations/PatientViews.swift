import SwiftUI

// MARK: - Pacientes: buscar antes de registrar (POST /pacientes/busquedas), alta, ficha, corrección e inactivación

/// Buscador de pacientes. El alta solo aparece después de una búsqueda: el token que exige la API viene de ella.
struct PatientsView: View {
    let user: UserProfile
    let api: APIClient?
    @State private var query = ""
    @State private var searching = false
    @State private var searchError: String?
    @State private var outcome: PatientSearchResult?
    @State private var outcomeQuery = ""
    @State private var registering = false

    var body: some View {
        ScreenScaffold(label: "PACIENTES / CLIMESA", title: "Pacientes.", titleSize: 30) {
            if PatientRules.canSearch(user.access) {
                if let searchError {
                    Banner(kind: .error, text: searchError)
                }
                PlainField(label: "Nombre, DUI o expediente", text: $query, prompt: "Mínimo 3 caracteres")
                PrimaryButton(title: searching ? "Buscando…" : "Buscar", isEnabled: !searching) { search() }
                if let outcome {
                    resultsSection(outcome)
                }
            } else {
                Banner(kind: .error, text: "Tu cuenta no tiene acceso a la búsqueda de pacientes.")
            }
        }
        .sheet(isPresented: $registering) {
            if let outcome {
                PatientFormSheet(mode: .create(search: outcome, query: outcomeQuery), user: user, api: api) {}
            }
        }
    }

    private func search() {
        guard !searching else { return }
        guard let api else {
            searchError = "Falta configurar el servidor de Climesa."
            return
        }
        if let problem = PatientRules.searchError(query) {
            searchError = problem
            return
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            searching = true
            defer { searching = false }
            do {
                let result = try await api.post("/pacientes/busquedas", body: PatientSearchRequest(query: text),
                                                as: PatientSearchResult.self)
                outcome = result
                outcomeQuery = text
                searchError = nil
            } catch is CancellationError {
                return
            } catch let error as ClientError {
                searchError = error.localizedDescription
            } catch {
                searchError = "No se pudo buscar. Revisa tu conexión e inténtalo de nuevo."
            }
        }
    }

    @ViewBuilder
    private func resultsSection(_ result: PatientSearchResult) -> some View {
        SectionTitle(text: "Coincidencias para “\(outcomeQuery)”")
        if result.candidates.isEmpty {
            BodyText(text: "No hay coincidencias. Revisa el dato o registra un paciente nuevo.")
        }
        ForEach(result.candidates) { patient in
            NavigationLink {
                PatientFileView(patient: patient, user: user, api: api)
            } label: {
                PatientRow(patient: patient)
            }
            .buttonStyle(.plain)
        }
        if PatientRules.canRegister(user.access) {
            SecondaryButton(title: "Registrar paciente nuevo") { registering = true }
        }
    }
}

struct PatientRow: View {
    let patient: PatientRecord

    var body: some View {
        Card {
            Text(patient.fullName)
                .font(.system(size: 15, weight: .semibold)).tracking(-0.2).foregroundColor(Theme.ink)
            Text("Expediente " + (patient.record ?? "sin número"))
                .font(.system(size: 12)).foregroundColor(Theme.muted)
            Pill(text: patient.isActive ? "Activo" : "Inactivo",
                 fg: patient.isActive ? Theme.ink : Theme.errorText,
                 bg: patient.isActive ? Theme.infoBg : Theme.errorBg)
        }
    }
}

/// Ficha del paciente (GET /pacientes/{id}): datos, historial y acciones según permisos del catálogo.
struct PatientFileView: View {
    let patient: PatientRecord
    let user: UserProfile
    let api: APIClient?
    @StateObject private var resource: RemoteResource<PatientFile>
    @State private var editing = false
    @State private var changingState = false

    init(patient: PatientRecord, user: UserProfile, api: APIClient?) {
        self.patient = patient
        self.user = user
        self.api = api
        _resource = StateObject(wrappedValue: RemoteResource<PatientFile>(api: api, path: "/pacientes/\(patient.id)"))
    }

    var body: some View {
        Group {
            if PatientRules.canViewFile(user.access) {
                ResourceContent(resource: resource, loadingText: "Consultando la ficha…") { file in
                    fileContent(file)
                }
            } else {
                Banner(kind: .error, text: "Tu cuenta no tiene acceso a la ficha de este paciente.")
                    .padding(24)
            }
        }
        .background(Theme.background)
        .navigationTitle(patient.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await resource.reload() }
        .sheet(isPresented: $editing) {
            if let file = resource.value {
                PatientFormSheet(mode: .edit(file.patient), user: user, api: api) {
                    Task { await resource.load(showSpinner: false) }
                }
            }
        }
        .sheet(isPresented: $changingState) {
            if let file = resource.value {
                PatientStateSheet(patient: file.patient, user: user, api: api) {
                    Task { await resource.load(showSpinner: false) }
                }
            }
        }
    }

    @ViewBuilder
    private func fileContent(_ file: PatientFile) -> some View {
        ScreenScaffold(label: "PACIENTES / CLIMESA", title: file.patient.fullName, titleSize: 26,
                       refresh: { await resource.load(showSpinner: false) }) {
            Card {
                DetailRow(label: "Expediente", value: file.patient.record ?? "Sin número")
                DetailRow(label: "DUI", value: file.patient.dui ?? "No registrado")
                DetailRow(label: "Fecha de nacimiento", value: file.patient.birth.map { String($0.prefix(10)) } ?? "No registrada")
                DetailRow(label: "Sexo", value: sexTitle(file.patient.sex))
                DetailRow(label: "Teléfono", value: file.patient.phone ?? "No registrado")
                DetailRow(label: "Estado", value: file.patient.isActive ? "Activo" : "Inactivo")
            }

            if PatientRules.canEdit(user.access) {
                SecondaryButton(title: "Corregir datos") { editing = true }
                LinkButton(title: file.patient.isActive ? "Inactivar paciente" : "Reactivar paciente") {
                    changingState = true
                }
            }

            SectionTitle(text: "Historial de cambios")
            if file.history.isEmpty {
                BodyText(text: "Sin cambios registrados.")
            }
            ForEach(file.history.sorted { $0.version > $1.version }) { entry in
                Card {
                    Text("Versión \(entry.version) · \(OperationsDates.text(entry.at))")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.ink)
                    Text(entry.reason).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
        }
    }

    private func sexTitle(_ code: String?) -> String {
        guard let code, let sex = PatientSex(rawValue: code) else { return "No registrado" }
        return sex.title
    }
}

/// Alta (después de buscar) o corrección de datos (con versión y motivo de 10 a 500 caracteres).
struct PatientFormSheet: View {
    enum Mode {
        case create(search: PatientSearchResult, query: String)
        case edit(PatientRecord)
    }

    let mode: Mode
    let user: UserProfile
    let api: APIClient?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var action = ActionModel()
    @State private var draft: PatientDraft
    @State private var reason = ""

    init(mode: Mode, user: UserProfile, api: APIClient?, onSaved: @escaping () -> Void) {
        self.mode = mode
        self.user = user
        self.api = api
        self.onSaved = onSaved
        switch mode {
        case .create:
            _draft = State(initialValue: PatientDraft())
        case .edit(let record):
            _draft = State(initialValue: PatientDraft(record: record))
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        SheetScaffold(title: isEdit ? "Corregir datos" : "Registrar paciente") {
            if action.conflict {
                Banner(kind: .error, text: "El paciente cambió. Cierra y vuelve a abrir la ficha para ver sus datos actuales; el cambio no se guardó.")
                SecondaryButton(title: "Cerrar") {
                    onSaved()
                    dismiss()
                }
            } else {
                if let message = action.error {
                    Banner(kind: .error, text: message)
                }
                if !isEdit {
                    BodyText(text: "Los datos se guardan solo si la búsqueda previa sigue vigente.")
                }
                PlainField(label: "Nombres", text: $draft.givenNames, prompt: "Nombres")
                PlainField(label: "Apellidos", text: $draft.surnames, prompt: "Apellidos")
                Picker("Sexo", selection: $draft.sex) {
                    Text("Sin elegir").tag(PatientSex?.none)
                    ForEach(PatientSex.allCases, id: \.self) { option in
                        Text(option.title).tag(PatientSex?.some(option))
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.blue)
                PlainField(label: "DUI (opcional)", text: $draft.dui, prompt: "00000000-0")
                PlainField(label: "Fecha de nacimiento (opcional)", text: $draft.birth, prompt: "AAAA-MM-DD")
                PlainField(label: "Teléfono (opcional)", text: $draft.phone, prompt: "8 dígitos")
                if isEdit {
                    PlainField(label: "Motivo de la corrección", text: $reason, prompt: "Al menos 10 caracteres", axis: .vertical)
                }
                PrimaryButton(title: action.busy ? "Guardando…" : "Guardar", isEnabled: !action.busy) { submit() }
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
        case .create(let search, let query):
            switch PatientRules.prepareCreate(draft, searchQuery: query, search: search, profile: user.access, now: Date()) {
            case .failure(let problem):
                action.fail(problem.message)
            case .success(let request):
                Task {
                    let saved = await action.run({ try await api.post("/pacientes", body: request) })
                    if saved {
                        onSaved()
                        dismiss()
                    }
                }
            }
        case .edit(let record):
            switch PatientRules.prepareUpdate(draft, current: record, reason: reason, profile: user.access) {
            case .failure(let problem):
                action.fail(problem.message)
            case .success(let request):
                let path = "/pacientes/\(record.id)"
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

/// Inactiva o reactiva un paciente con motivo. La API conserva el registro y su historial.
struct PatientStateSheet: View {
    let patient: PatientRecord
    let user: UserProfile
    let api: APIClient?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var action = ActionModel()
    @State private var reason = ""

    private var deactivating: Bool { patient.isActive }

    var body: some View {
        SheetScaffold(title: deactivating ? "Inactivar paciente" : "Reactivar paciente") {
            if action.conflict {
                Banner(kind: .error, text: "El paciente cambió. Cierra y vuelve a abrir la ficha para ver su estado actual; el cambio no se guardó.")
                SecondaryButton(title: "Cerrar") {
                    onSaved()
                    dismiss()
                }
            } else {
                if let message = action.error {
                    Banner(kind: .error, text: message)
                }
                BodyText(text: deactivating
                         ? "\(patient.fullName) quedará inactivo. El registro no se borra y tu motivo queda en el historial."
                         : "\(patient.fullName) volverá a quedar activo. Tu motivo queda en el historial.")
                PlainField(label: "Motivo", text: $reason, prompt: "Al menos 10 caracteres", axis: .vertical)
                PrimaryButton(title: action.busy ? "Guardando…" : (deactivating ? "Inactivar" : "Reactivar"),
                              isEnabled: !action.busy, tint: deactivating ? Theme.errorText : Theme.blue) { submit() }
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
        switch PatientRules.prepareStateChange(patient, active: !patient.isActive, reason: reason, profile: user.access) {
        case .failure(let problem):
            action.fail(problem.message)
        case .success(let request):
            let path = "/pacientes/\(patient.id)/estado"
            Task {
                let saved = await action.run({ try await api.post(path, body: request) })
                if saved {
                    onSaved()
                    dismiss()
                }
            }
        }
    }
}
