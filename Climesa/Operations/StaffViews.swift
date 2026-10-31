import SwiftUI

// MARK: - Directorio de personal (GET /personal) y ficha

struct StaffDirectoryView: View {
    let user: UserProfile
    let api: APIClient?
    let liveVersion: Int
    @StateObject private var resource: RemoteResource<[StaffMember]>
    @State private var query = ""
    @State private var scope: StaffScope = .activos

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
    }

    @ViewBuilder
    private func staffList(_ people: [StaffMember]) -> some View {
        let rows = StaffDirectory.filter(people, query: query, scope: scope)
        if rows.isEmpty {
            Text("No hay personas en esta vista.").font(.system(size: 13)).foregroundColor(Theme.muted)
        }
        ForEach(rows) { person in
            NavigationLink {
                StaffDetailView(person: person, user: user, api: api, liveVersion: liveVersion)
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

    var body: some View {
        ScreenScaffold(label: "PERSONAL / CLIMESA", title: person.fullName, titleSize: 26) {
            Card {
                DetailRow(label: "Función", value: StaffLabels.function(person.type))
                DetailRow(label: "Especialidad", value: valueOrDash(person.specialty, empty: "Sin especialidad registrada"))
                DetailRow(label: "Área", value: valueOrDash(person.area, empty: "Sin asignar"))
                DetailRow(label: "Estado", value: person.isActive ? "Activo" : "Inactivo")
            }

            SectionTitle(text: "Inscripciones profesionales")
            registrations

            if user.access.hasPermission(OperationPermission.viewShifts) {
                SectionTitle(text: "Turnos próximos")
                UpcomingShiftsSection(staffId: person.id, api: api, liveVersion: liveVersion)
            }
        }
        .background(Theme.background)
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
