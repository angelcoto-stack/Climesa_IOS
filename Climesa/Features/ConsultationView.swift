import SwiftUI

@MainActor
final class ConsultationViewModel: ObservableObject {
    let user: UserProfile
    private let backend = HospitalBackend.shared

    @Published var items: [ConsultationInfo] = []
    @Published var patients: [PatientSummary] = []
    @Published var message: String?

    init(user: UserProfile) { self.user = user }

    var canCreate: Bool { user.role == .doctor }

    func load() async {
        do { items = try await backend.consultations(for: user) } catch { message = error.localizedDescription }
        if canCreate { patients = (try? await backend.patients(for: user)) ?? [] }
    }

    func create(patientId: UUID, diagnosis: String, prescription: String, exams: String) async -> Bool {
        let list = exams.split(separator: ",").map { String($0) }
        do {
            try await backend.createConsultation(patientId: patientId, diagnosis: diagnosis,
                                                 prescription: prescription, exams: list, by: user)
            message = nil
            await load()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}

struct ConsultationView: View {
    @StateObject private var vm: ConsultationViewModel
    @State private var showNew = false

    init(user: UserProfile) { _vm = StateObject(wrappedValue: ConsultationViewModel(user: user)) }

    var body: some View {
        ScreenScaffold(label: vm.user.role == .paciente ? "HISTORIAL / 01" : "CONSULTA GENERAL / 01",
                       title: vm.user.role == .paciente ? "Tu historial." : "Consulta.",
                       subtitle: "Diagnósticos, recetas y solicitudes de examen. Expediente protegido: solo médico tratante y paciente.",
                       refresh: { await vm.load() }) {
            if let m = vm.message { Banner(kind: .error, text: m) }
            if vm.canCreate {
                PrimaryButton(title: "Nueva consulta") { showNew = true }
            }
            if vm.items.isEmpty {
                Text("Sin consultas registradas.").font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            ForEach(vm.items) { item in
                Card {
                    Text(item.consultation.date.formatted(date: .long, time: .shortened))
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.blue)
                    if vm.user.role != .paciente {
                        Text(item.patientName).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    } else {
                        Text(item.doctorName).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.ink)
                    }
                    labeled("Diagnóstico", item.consultation.diagnosis)
                    if !item.consultation.prescription.isEmpty {
                        labeled("Receta", item.consultation.prescription)
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showNew) { NewConsultationSheet(vm: vm) }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10.5)).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 14)).foregroundColor(Theme.ink)
        }
    }
}

struct NewConsultationSheet: View {
    @ObservedObject var vm: ConsultationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var patientId: UUID?
    @State private var diagnosis = ""
    @State private var prescription = ""
    @State private var exams = ""

    var body: some View {
        SheetScaffold(title: "Nueva consulta") {
            PatientPickerRow(patients: vm.patients, selection: $patientId)
            PlainField(label: "Diagnóstico", text: $diagnosis, prompt: "Describe el diagnóstico", axis: .vertical)
            PlainField(label: "Receta", text: $prescription, prompt: "Medicamento y dosis", axis: .vertical)
            PlainField(label: "Exámenes (separados por coma)", text: $exams, prompt: "Hemograma, Glucosa")
            PrimaryButton(title: "Guardar consulta", isEnabled: patientId != nil) {
                guard let id = patientId else { return }
                Task {
                    if await vm.create(patientId: id, diagnosis: diagnosis, prescription: prescription, exams: exams) {
                        dismiss()
                    }
                }
            }
            if let m = vm.message { Banner(kind: .error, text: m) }
        }
    }
}
