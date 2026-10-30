import SwiftUI

@MainActor
final class RoomsViewModel: ObservableObject {
    let user: UserProfile
    private let backend = HospitalBackend.shared

    @Published var rooms: [RoomInfo] = []
    @Published var patients: [PatientSummary] = []
    @Published var message: String?
    @Published var success: String?

    init(user: UserProfile) { self.user = user }

    var canManage: Bool { [.administrador, .recepcionista, .asistente].contains(user.role) }
    var unassigned: [PatientSummary] { patients.filter { $0.roomId == nil } }

    func load() async {
        rooms = await backend.rooms(for: user)
        if canManage { patients = (try? await backend.patients(for: user)) ?? [] }
    }

    func assign(patientId: UUID, roomId: String) async -> Bool {
        await run { try await self.backend.assign(patientId: patientId, roomId: roomId, by: self.user) }
    }

    func autoAssign(patientId: UUID, kind: RoomKind) async -> Bool {
        do {
            let room = try await backend.autoAssign(patientId: patientId, kind: kind, by: user)
            message = nil
            success = "Paciente asignado a \(room)."
            await load()
            return true
        } catch {
            success = nil
            message = error.localizedDescription
            return false
        }
    }

    func discharge(patientId: UUID) async {
        _ = await run { try await self.backend.discharge(patientId: patientId, by: self.user) }
    }

    private func run(_ op: () async throws -> Void) async -> Bool {
        do {
            try await op()
            message = nil
            success = nil
            await load()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}

struct RoomGroup: Identifiable {
    let id: String
    let rooms: [RoomInfo]
}

struct RoomsView: View {
    @StateObject private var vm: RoomsViewModel
    @State private var assigning: RoomInfo?
    @State private var showAuto = false

    init(user: UserProfile) { _vm = StateObject(wrappedValue: RoomsViewModel(user: user)) }

    private var groups: [RoomGroup] {
        [RoomGroup(id: "3ª planta · VIP individuales", rooms: vm.rooms.filter { $0.floor == 3 }),
         RoomGroup(id: "2ª planta · Semiprivadas (2 pacientes)", rooms: vm.rooms.filter { $0.floor == 2 })]
            .filter { !$0.rooms.isEmpty }
    }

    var body: some View {
        ScreenScaffold(label: vm.user.role == .paciente ? "MI HABITACIÓN / 01" : "INFRAESTRUCTURA / 01",
                       title: vm.user.role == .paciente ? "Tu habitación." : "Habitaciones.",
                       subtitle: vm.user.role == .paciente
                           ? "La asignación de tu cama es información privada."
                           : "5 VIP en la 3ª planta y 6 semiprivadas en la 2ª. Sin sobrecupo ni doble asignación.",
                       refresh: { await vm.load() }) {
            if let m = vm.message { Banner(kind: .error, text: m) }
            if let s = vm.success { Banner(kind: .info, text: s) }

            if vm.canManage {
                SecondaryButton(title: "Asignación automática") { showAuto = true }
            }
            if vm.rooms.isEmpty && vm.user.role == .paciente {
                Banner(kind: .info, text: "Actualmente no tienes una habitación asignada.")
            }

            ForEach(groups) { group in
                SectionTitle(text: group.id)
                ForEach(group.rooms) { room in roomCard(room) }
            }
        }
        .task { await vm.load() }
        .sheet(item: $assigning) { room in
            AssignSheet(vm: vm, room: room)
        }
        .sheet(isPresented: $showAuto) {
            AutoAssignSheet(vm: vm)
        }
    }

    @ViewBuilder
    private func roomCard(_ room: RoomInfo) -> some View {
        Card {
            HStack {
                Text(room.id).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(Theme.ink)
                Spacer()
                Pill(text: "\(room.occupants.count)/\(room.capacity)",
                     fg: room.isFull ? Theme.errorText : Theme.okText,
                     bg: room.isFull ? Theme.errorBg : Theme.infoBg)
            }
            ForEach(room.occupants) { o in
                HStack {
                    Image(systemName: o.name == nil ? "lock" : "person")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                    Text(o.name ?? "Paciente protegido")
                        .font(.system(size: 14))
                        .foregroundColor(o.name == nil ? Theme.muted : Theme.ink)
                    Spacer()
                    if vm.canManage {
                        Button("Dar de alta") { Task { await vm.discharge(patientId: o.patientId) } }
                            .font(.system(size: 12)).foregroundColor(Theme.errorText)
                    }
                }
            }
            if !room.isFull && vm.canManage {
                Button { assigning = room } label: {
                    Text(room.occupants.isEmpty ? "Asignar paciente" : "Asignar segunda cama")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.blue)
                }
            }
        }
    }
}

struct AssignSheet: View {
    @ObservedObject var vm: RoomsViewModel
    let room: RoomInfo
    @Environment(\.dismiss) private var dismiss
    @State private var patientId: UUID?

    var body: some View {
        SheetScaffold(title: "Asignar a \(room.id)") {
            BodyText(text: "Solo se listan pacientes sin cama asignada.")
            PatientPickerRow(patients: vm.unassigned, selection: $patientId)
            PrimaryButton(title: "Asignar", isEnabled: patientId != nil) {
                guard let id = patientId else { return }
                Task { if await vm.assign(patientId: id, roomId: room.id) { dismiss() } }
            }
            if let m = vm.message { Banner(kind: .error, text: m) }
        }
    }
}

struct AutoAssignSheet: View {
    @ObservedObject var vm: RoomsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var patientId: UUID?
    @State private var kind: RoomKind = .semiprivada

    var body: some View {
        SheetScaffold(title: "Asignación automática") {
            BodyText(text: "VIP: primera habitación libre. Semiprivada: completa primero las habitaciones con una cama ocupada.")
            PatientPickerRow(patients: vm.unassigned, selection: $patientId)
            Picker("Tipo", selection: $kind) {
                Text("Semiprivada").tag(RoomKind.semiprivada)
                Text("VIP").tag(RoomKind.vip)
            }
            .pickerStyle(.segmented)
            PrimaryButton(title: "Asignar cama", isEnabled: patientId != nil) {
                guard let id = patientId else { return }
                Task { if await vm.autoAssign(patientId: id, kind: kind) { dismiss() } }
            }
            if let m = vm.message { Banner(kind: .error, text: m) }
        }
    }
}
