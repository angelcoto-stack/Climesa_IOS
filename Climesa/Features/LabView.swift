import SwiftUI

@MainActor
final class LabViewModel: ObservableObject {
    let user: UserProfile
    private let backend = HospitalBackend.shared

    @Published var labs: [LabInfo] = []
    @Published var patients: [PatientSummary] = []
    @Published var message: String?

    init(user: UserProfile) { self.user = user }

    var canCreate: Bool { user.role == .doctor }
    var canAdvance: Bool { [.administrador, .asistente, .doctor].contains(user.role) }

    func load() async {
        do { labs = try await backend.labs(for: user) } catch { message = error.localizedDescription }
        if canCreate { patients = (try? await backend.patients(for: user)) ?? [] }
    }

    func create(patientId: UUID, exam: String) async -> Bool {
        do {
            try await backend.createLab(patientId: patientId, exam: exam, by: user)
            message = nil
            await load()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func advance(_ lab: LabInfo, result: String?) async -> Bool {
        do {
            try await backend.advanceLab(id: lab.id, result: result, by: user)
            message = nil
            await load()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}

struct LabView: View {
    @StateObject private var vm: LabViewModel
    @State private var showNew = false
    @State private var completing: LabInfo?

    init(user: UserProfile) { _vm = StateObject(wrappedValue: LabViewModel(user: user)) }

    var body: some View {
        ScreenScaffold(label: "LABORATORIO / 01",
                       title: vm.user.role == .paciente ? "Tus resultados." : "Laboratorio.",
                       subtitle: "Estados: Pendiente, En proceso y Completado. Los resultados son información protegida.",
                       refresh: { await vm.load() }) {
            if let m = vm.message { Banner(kind: .error, text: m) }
            if vm.canCreate {
                PrimaryButton(title: "Nueva orden de laboratorio") { showNew = true }
            }
            if vm.labs.isEmpty {
                Text("Sin órdenes registradas.").font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            ForEach(vm.labs) { lab in
                Card {
                    HStack {
                        Text(lab.order.exam).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                        Spacer()
                        statusPill(lab.order.status)
                    }
                    if vm.user.role != .paciente {
                        Text("Paciente: \(lab.patientName)").font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                    Text("Solicitó: \(lab.doctorName) · \(lab.order.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                    if let result = lab.order.result {
                        Banner(kind: .info, text: result)
                    }
                    if vm.canAdvance && lab.order.status != .completado {
                        SecondaryButton(title: lab.order.status == .pendiente ? "Marcar En proceso" : "Registrar resultado") {
                            if lab.order.status == .pendiente {
                                Task { _ = await vm.advance(lab, result: nil) }
                            } else {
                                completing = lab
                            }
                        }
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showNew) { NewLabSheet(vm: vm) }
        .sheet(item: $completing) { lab in CompleteLabSheet(vm: vm, lab: lab) }
    }

    @ViewBuilder
    private func statusPill(_ s: LabStatus) -> some View {
        switch s {
        case .pendiente: Pill(text: s.title, fg: Theme.errorText, bg: Theme.errorBg)
        case .enProceso: Pill(text: s.title, fg: .white, bg: Theme.blue)
        case .completado: Pill(text: s.title, fg: Theme.okText, bg: Theme.infoBg)
        }
    }
}

struct NewLabSheet: View {
    @ObservedObject var vm: LabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var patientId: UUID?
    @State private var exam = ""

    var body: some View {
        SheetScaffold(title: "Nueva orden") {
            PatientPickerRow(patients: vm.patients, selection: $patientId)
            PlainField(label: "Examen", text: $exam, prompt: "Ej. Hemograma completo")
            PrimaryButton(title: "Emitir orden", isEnabled: patientId != nil) {
                guard let id = patientId else { return }
                Task { if await vm.create(patientId: id, exam: exam) { dismiss() } }
            }
            if let m = vm.message { Banner(kind: .error, text: m) }
        }
    }
}

struct CompleteLabSheet: View {
    @ObservedObject var vm: LabViewModel
    let lab: LabInfo
    @Environment(\.dismiss) private var dismiss
    @State private var result = ""

    var body: some View {
        SheetScaffold(title: lab.order.exam) {
            BodyText(text: "Paciente: \(lab.patientName)")
            PlainField(label: "Resultado", text: $result, prompt: "Describe el resultado", axis: .vertical)
            PrimaryButton(title: "Completar examen") {
                Task { if await vm.advance(lab, result: result) { dismiss() } }
            }
            if let m = vm.message { Banner(kind: .error, text: m) }
        }
    }
}
