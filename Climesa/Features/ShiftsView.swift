import SwiftUI

@MainActor
final class ShiftsViewModel: ObservableObject {
    let user: UserProfile
    private let backend = HospitalBackend.shared

    @Published var shifts: [Shift] = []
    @Published var message: String?

    init(user: UserProfile) { self.user = user }

    var isAdmin: Bool { user.role == .administrador }

    func load() async { shifts = await backend.shifts(for: user) }

    func add(name: String, title: StaffTitle, weekday: Int, start: Int, end: Int) async -> Bool {
        do {
            try await backend.addShift(staffName: name, title: title, weekday: weekday, start: start, end: end, by: user)
            message = nil
            await load()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func remove(_ shift: Shift) async {
        try? await backend.removeShift(id: shift.id, by: user)
        await load()
    }
}

struct ShiftsView: View {
    @StateObject private var vm: ShiftsViewModel
    @State private var showNew = false

    init(user: UserProfile) { _vm = StateObject(wrappedValue: ShiftsViewModel(user: user)) }

    private var days: [Int] { Array(Set(vm.shifts.map(\.weekday))).sorted() }

    var body: some View {
        ScreenScaffold(label: "TURNOS DEL PERSONAL / 01",
                       title: "Turnos.",
                       subtitle: "Doctores, enfermeras, alergistas, emergencia, asistentes y recepción.",
                       refresh: { await vm.load() }) {
            if let m = vm.message { Banner(kind: .error, text: m) }
            if vm.isAdmin {
                PrimaryButton(title: "Agregar turno") { showNew = true }
            }
            ForEach(days, id: \.self) { day in
                SectionTitle(text: Shift.weekdayNames[day])
                let items = vm.shifts.filter { $0.weekday == day }.sorted { $0.startMinutes < $1.startMinutes }
                Card {
                    ForEach(items) { shift in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shift.staffName).font(.system(size: 14)).foregroundColor(Theme.ink)
                                Text(shift.title.title).font(.system(size: 11)).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            Text(shift.range).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.ink)
                            if vm.isAdmin {
                                Button { Task { await vm.remove(shift) } } label: {
                                    Image(systemName: "trash").font(.system(size: 12)).foregroundColor(Theme.errorText)
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showNew) { NewShiftSheet(vm: vm) }
    }
}

struct NewShiftSheet: View {
    @ObservedObject var vm: ShiftsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var title: StaffTitle = .doctor
    @State private var weekday = 0
    @State private var start = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()

    private func minutes(_ d: Date) -> Int {
        Calendar.current.component(.hour, from: d) * 60 + Calendar.current.component(.minute, from: d)
    }

    var body: some View {
        SheetScaffold(title: "Agregar turno") {
            PlainField(label: "Nombre del personal", text: $name, prompt: "Ej. Dra. Elena Cruz")
            Picker("Cargo", selection: $title) {
                ForEach(StaffTitle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu).tint(Theme.blue)
            Picker("Día", selection: $weekday) {
                ForEach(0..<7, id: \.self) { Text(Shift.weekdayNames[$0]).tag($0) }
            }
            .pickerStyle(.menu).tint(Theme.blue)
            DatePicker("Inicio", selection: $start, displayedComponents: .hourAndMinute)
            DatePicker("Fin", selection: $end, displayedComponents: .hourAndMinute)
            PrimaryButton(title: "Guardar turno") {
                Task {
                    if await vm.add(name: name, title: title, weekday: weekday,
                                    start: minutes(start), end: minutes(end)) { dismiss() }
                }
            }
            if let m = vm.message { Banner(kind: .error, text: m) }
        }
    }
}
