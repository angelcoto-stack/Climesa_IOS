import SwiftUI

@MainActor
final class AmbulanceViewModel: ObservableObject {
    enum LogFilter: String, CaseIterable, Identifiable {
        case today = "Hoy", week = "7 días", all = "Todo"
        var id: String { rawValue }
        var since: Date? {
            switch self {
            case .today: return Calendar.current.startOfDay(for: Date())
            case .week: return Date().addingTimeInterval(-7 * 86_400)
            case .all: return nil
            }
        }
    }

    let user: UserProfile
    private let backend = HospitalBackend.shared

    @Published var snapshot = AmbulanceSnapshot(state: .disponible, pending: nil, active: nil)
    @Published var log: [AmbulanceLogEntry] = []
    @Published var filter: LogFilter = .week
    @Published var message: String?
    @Published var isBusy = false

    init(user: UserProfile) { self.user = user }

    var isAdmin: Bool { user.role == .administrador }
    var isPatient: Bool { user.role == .paciente }
    var canOperate: Bool { user.role != .paciente }

    func load() async {
        snapshot = await backend.ambulance(for: user)
        if !isPatient {
            log = (try? await backend.ambulanceLog(for: user, since: filter.since)) ?? []
        }
    }

    func perform(_ op: () async throws -> Void) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await op()
            message = nil
            await load()
            return true
        } catch {
            message = error.localizedDescription
            await load()
            return false
        }
    }

    func request(reason: String, destination: String) async -> Bool {
        await perform { try await self.backend.requestAmbulance(reason: reason, destination: destination, by: self.user) }
    }
    func dispatch() async { _ = await perform { try await self.backend.dispatchPending(by: self.user) } }
    func cancel() async { _ = await perform { try await self.backend.cancelPending(by: self.user) } }
    func finish() async { _ = await perform { try await self.backend.finishService(by: self.user) } }
    func maintenance(_ on: Bool) async { _ = await perform { try await self.backend.setMaintenance(on, by: self.user) } }
}

struct AmbulanceView: View {
    @StateObject private var vm: AmbulanceViewModel
    @State private var showRequest = false

    init(user: UserProfile) { _vm = StateObject(wrappedValue: AmbulanceViewModel(user: user)) }

    private var stateColors: (fg: Color, bg: Color) {
        switch vm.snapshot.state {
        case .disponible: return (Theme.okText, Theme.infoBg)
        case .enServicio: return (.white, Theme.blue)
        case .enMantenimiento: return (Theme.errorText, Theme.errorBg)
        }
    }

    var body: some View {
        ScreenScaffold(label: "RECURSO CRÍTICO / 01",
                       title: "Ambulancia.",
                       subtitle: "El hospital cuenta con una sola unidad. El estado se actualiza en tiempo real.",
                       refresh: { await vm.load() }) {
            if let m = vm.message { Banner(kind: .error, text: m) }

            VStack(alignment: .leading, spacing: 6) {
                Text("ESTADO ACTUAL")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(stateColors.fg.opacity(0.8))
                Text(vm.snapshot.state.title)
                    .font(.system(size: 28, weight: .bold)).tracking(-1).foregroundColor(stateColors.fg)
                if let active = vm.snapshot.active {
                    Text("\(active.reason) → \(active.destination.isEmpty ? "sin destino" : active.destination)")
                        .font(.system(size: 12)).foregroundColor(stateColors.fg.opacity(0.9))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(stateColors.bg)

            if let p = vm.snapshot.pending {
                Card {
                    Pill(text: "Solicitud pendiente", fg: Theme.errorText, bg: Theme.errorBg)
                    Text(p.patientName).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                    Text(p.reason).font(.system(size: 13)).foregroundColor(Theme.muted)
                    if vm.canOperate {
                        PrimaryButton(title: "Despachar ambulancia", isEnabled: !vm.isBusy && vm.snapshot.state == .disponible) {
                            Task { await vm.dispatch() }
                        }
                    }
                    SecondaryButton(title: vm.isPatient ? "Cancelar solicitud" : "Rechazar solicitud", isEnabled: !vm.isBusy) {
                        Task { await vm.cancel() }
                    }
                }
            }

            actions

            if vm.canOperate { logSection }
        }
        .task {
            // Sondeo cada 3 s mientras la vista esté visible (simula tiempo real).
            while !Task.isCancelled {
                await vm.load()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .sheet(isPresented: $showRequest) { RequestAmbulanceSheet(vm: vm) }
    }

    @ViewBuilder
    private var actions: some View {
        switch vm.snapshot.state {
        case .disponible:
            if vm.snapshot.pending == nil {
                PrimaryButton(title: vm.isPatient ? "Solicitar ambulancia" : "Despachar ambulancia",
                              isEnabled: !vm.isBusy) { showRequest = true }
            }
            if vm.isAdmin {
                SecondaryButton(title: "Enviar a mantenimiento", isEnabled: !vm.isBusy) { Task { await vm.maintenance(true) } }
            }
        case .enServicio:
            if vm.canOperate {
                PrimaryButton(title: "Finalizar servicio", isEnabled: !vm.isBusy) { Task { await vm.finish() } }
            } else {
                Banner(kind: .info, text: "La ambulancia está en servicio. Intenta de nuevo más tarde.")
            }
        case .enMantenimiento:
            if vm.isAdmin {
                PrimaryButton(title: "Marcar como disponible", isEnabled: !vm.isBusy) { Task { await vm.maintenance(false) } }
            } else {
                Banner(kind: .info, text: "La ambulancia está en mantenimiento.")
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        SectionTitle(text: "Bitácora de emergencias")
        Picker("Filtro", selection: $vm.filter) {
            ForEach(AmbulanceViewModel.LogFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: vm.filter) { _ in Task { await vm.load() } }

        if vm.log.isEmpty {
            Text("Sin registros en este periodo.").font(.system(size: 13)).foregroundColor(Theme.muted)
        }
        ForEach(vm.log) { entry in
            Card {
                HStack {
                    Text(entry.reason).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.ink)
                    Spacer()
                    Pill(text: entry.endedAt == nil ? "Activo" : "Cerrado",
                         fg: entry.endedAt == nil ? .white : Theme.ink,
                         bg: entry.endedAt == nil ? Theme.blue : Theme.infoBg)
                }
                Text("Destino: \(entry.destination.isEmpty ? "—" : entry.destination)")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                Text("Solicitó: \(entry.requestedBy) · Despachó: \(entry.dispatchedBy)")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened)
                     + (entry.endedAt.map { " → " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.muted)
            }
        }
    }
}

struct RequestAmbulanceSheet: View {
    @ObservedObject var vm: AmbulanceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var destination = ""

    var body: some View {
        SheetScaffold(title: vm.isPatient ? "Solicitar ambulancia" : "Despachar ambulancia") {
            PlainField(label: "Motivo de la emergencia", text: $reason, prompt: "Ej. dolor torácico", axis: .vertical)
            PlainField(label: "Destino", text: $destination, prompt: "Ej. Hospital Nacional")
            PrimaryButton(title: vm.isPatient ? "Enviar solicitud" : "Despachar", isEnabled: !vm.isBusy) {
                Task { if await vm.request(reason: reason, destination: destination) { dismiss() } }
            }
            if let m = vm.message { Banner(kind: .error, text: m) }
        }
    }
}
