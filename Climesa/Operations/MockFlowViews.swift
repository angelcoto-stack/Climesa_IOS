import SwiftUI

// MARK: - Maquetas de los flujos de médico y paciente (datos ficticios; no llaman a la API)
// Cada pantalla se puede recorrer. Las acciones muestran un aviso de maqueta y no guardan nada.
// Las propiedades de estado no son `private` a propósito: así el init memberwise sigue siendo accesible.

/// Aviso fijo que recuerda que la pantalla es una maqueta.
struct MockNotice: View {
    var body: some View {
        Banner(kind: .info, text: "Maqueta: datos ficticios. Esta pantalla todavía no guarda nada.")
    }
}

/// Fila de lista con título, detalle y una etiqueta opcional.
struct MockRow: View {
    let title: String
    let detail: String
    var tag: String? = nil
    var alert: Bool = false

    var body: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold)).tracking(-0.2)
                        .foregroundColor(alert ? Theme.errorText : Theme.ink)
                    Text(detail).font(.system(size: 12.5)).foregroundColor(Theme.muted)
                }
                Spacer()
                if let tag = tag {
                    Pill(text: tag, fg: alert ? Theme.errorText : Theme.ink, bg: alert ? Theme.errorBg : Theme.infoBg)
                }
            }
        }
    }
}

/// Botón de navegación con el mismo aspecto que `PrimaryButton`.
struct MockBlueLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Theme.blue)
    }
}

// MARK: - Datos ficticios de exámenes

struct MockValue: Identifiable {
    let name: String
    let result: String
    let range: String
    let unit: String

    var id: String { name }
}

struct MockExam: Identifiable {
    let id: String
    let name: String
    let state: String
    let reviewed: Bool
    let critical: Bool
    let values: [MockValue]
}

private let mockExamSamples: [MockExam] = [
    MockExam(id: "ex1", name: "Hematología completa", state: "Completado", reviewed: true, critical: false, values: [
        MockValue(name: "Hemoglobina", result: "13.5", range: "12.0 – 15.5", unit: "g/dL"),
        MockValue(name: "Leucocitos", result: "7.1", range: "4.0 – 11.0", unit: "x10^3/µL")
    ]),
    MockExam(id: "ex2", name: "Glucosa en ayunas", state: "En proceso", reviewed: false, critical: false, values: [
        MockValue(name: "Glucosa", result: "98", range: "70 – 99", unit: "mg/dL")
    ]),
    MockExam(id: "ex3", name: "Potasio", state: "Completado", reviewed: false, critical: true, values: [
        MockValue(name: "Potasio", result: "6.4", range: "3.5 – 5.1", unit: "mmol/L")
    ])
]

// MARK: - Paciente

/// Mi número o fila: número grande y cuánto falta.
struct MockFilaView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Mi turno.", titleSize: 30) {
            MockNotice()
            Card {
                Text("Tu número")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.muted)
                Text("B-042")
                    .font(.system(size: 56, weight: .bold)).foregroundColor(Theme.blue)
                DetailRow(label: "Personas antes que tú", value: "6")
                DetailRow(label: "Consultorio al ser llamado", value: "Consultorio 3")
                DetailRow(label: "Servicio", value: "Medicina interna")
            }
            BodyText(text: "Te avisamos cuando llegue tu turno.")
        }
    }
}

/// Mis citas: próximas y pasadas, con "Pedir cita" solo si el catálogo lo permite.
struct MockCitasView: View {
    let user: UserProfile

    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Mis citas.", titleSize: 30) {
            MockNotice()
            if FlowVisibility.showsRequestAppointment(user.access) {
                NavigationLink {
                    MockPedirCitaView()
                } label: {
                    MockBlueLabel(title: "Pedir cita")
                }
                .buttonStyle(.plain)
            }
            SectionTitle(text: "Próximas")
            MockRow(title: "Dra. Ejemplo Prueba", detail: "Medicina interna · 12/11/2026 09:00", tag: "Confirmada")
            MockRow(title: "Dr. Ficticio Demo", detail: "Control · 20/11/2026 14:30", tag: "Pendiente")
            SectionTitle(text: "Pasadas")
            MockRow(title: "Dr. Ficticio Demo", detail: "Control · 03/08/2026 08:00", tag: "Atendida")
        }
    }
}

/// Pedir cita: especialidad, horario libre y solicitud de maqueta.
struct MockPedirCitaView: View {
    @State var specialty: String = "Medicina interna"
    @State var selectedSlot: String? = nil
    @State var sent: Bool = false

    let specialties = ["Medicina interna", "Pediatría", "Cardiología"]
    let slots = ["Lunes 09/11 · 08:00", "Lunes 09/11 · 10:30", "Martes 10/11 · 14:00"]

    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Pedir cita.", titleSize: 28) {
            MockNotice()
            Picker("Especialidad", selection: $specialty) {
                ForEach(specialties, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.blue)
            SectionTitle(text: "Horarios libres")
            ForEach(slots, id: \.self) { slot in
                Button {
                    selectedSlot = slot
                } label: {
                    HStack {
                        Text(slot).font(.system(size: 13.5)).foregroundColor(Theme.ink)
                        Spacer()
                        if selectedSlot == slot {
                            Image(systemName: "checkmark").foregroundColor(Theme.blue)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Theme.card)
                    .overlay(Rectangle().stroke(selectedSlot == slot ? Theme.blue : Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            PrimaryButton(title: "Solicitar horario", isEnabled: selectedSlot != nil) {
                sent = true
            }
            if sent {
                Banner(kind: .info, text: "Maqueta: la solicitud no se envió.")
            }
        }
    }
}

/// Exámenes y resultados: los valores se ocultan hasta que el médico los revisa.
struct MockExamenesView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Exámenes.", titleSize: 30) {
            MockNotice()
            ForEach(mockExamSamples) { exam in
                NavigationLink {
                    MockResultadoView(exam: exam, patientView: true)
                } label: {
                    MockRow(title: exam.name, detail: "Estado del examen", tag: exam.state)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Resultado con rangos. Para el paciente, los valores solo aparecen si el médico ya los revisó.
struct MockResultadoView: View {
    let exam: MockExam
    let patientView: Bool
    @State var marked: Bool = false

    var body: some View {
        ScreenScaffold(label: "MAQUETA / \(patientView ? "PACIENTE" : "MEDICINA")", title: exam.name, titleSize: 24) {
            MockNotice()
            if patientView && !exam.reviewed {
                BodyText(text: "Los valores aparecerán cuando tu médico los revise.")
            } else {
                ForEach(exam.values) { value in
                    Card {
                        DetailRow(label: value.name, value: "\(value.result) \(value.unit)")
                        DetailRow(label: "Rango de referencia", value: value.range)
                    }
                }
            }
            if !patientView {
                PrimaryButton(title: marked ? "Revisado" : "Marcar como revisado", isEnabled: !marked && !exam.reviewed) {
                    marked = true
                }
            }
        }
    }
}

/// Historial de consultas propias (solo lo revisado).
struct MockHistorialView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Mi historial.", titleSize: 30) {
            MockNotice()
            MockRow(title: "12/10/2026 · Dra. Ejemplo Prueba", detail: "Diagnóstico: faringitis aguda. Receta: paracetamol 500 mg.")
            MockRow(title: "03/08/2026 · Dr. Ficticio Demo", detail: "Diagnóstico: control de presión arterial. Sin receta.")
            BodyText(text: "Solo se muestran las consultas que tu médico ya revisó.")
        }
    }
}

/// Solicitar ambulancia: aviso 911, formulario y seguimiento de estados.
struct MockAmbulanciaView: View {
    @State var location: String = ""
    @State var reason: String = ""
    @State var sent: Bool = false
    @State var step: Int = 0
    let steps = ["Por confirmar", "Confirmada", "En camino", "Llegó"]

    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Ambulancia.", titleSize: 30) {
            MockNotice()
            Banner(kind: .error, text: "Si hay riesgo de vida, llama primero al 911.")
            if sent {
                SectionTitle(text: "Seguimiento")
                ForEach(Array(steps.enumerated()), id: \.offset) { entry in
                    MockRow(title: entry.element,
                            detail: entry.offset <= step ? "Completado" : "Pendiente",
                            tag: entry.offset == step ? "Actual" : nil)
                }
                PrimaryButton(title: "Avanzar estado (maqueta)", isEnabled: step < steps.count - 1) {
                    step += 1
                }
            } else {
                PlainField(label: "Ubicación", text: $location, prompt: "Dirección o punto de referencia")
                PlainField(label: "Motivo", text: $reason, prompt: "Describe lo que pasa", axis: .vertical)
                PrimaryButton(title: "Enviar solicitud",
                              isEnabled: !location.trimmingCharacters(in: .whitespaces).isEmpty) {
                    sent = true
                }
            }
        }
    }
}

// MARK: - Médico

/// Mi día: citas, números, pendientes y accesos a consulta y hospitalizados según permisos.
struct MockMiDiaView: View {
    let user: UserProfile

    var body: some View {
        ScreenScaffold(label: "MAQUETA / MEDICINA", title: "Mi día.", titleSize: 30) {
            MockNotice()
            SectionTitle(text: "Citas de hoy")
            MockRow(title: "08:00 · Ana Ficticia", detail: "Control · Consultorio 2", tag: "En espera")
            MockRow(title: "09:30 · Luis Demo", detail: "Primera vez · Consultorio 2", tag: "Agendada")
            SectionTitle(text: "Números asignados")
            MockRow(title: "B-017", detail: "Medicina interna · Consultorio 2", tag: "Llamado")
            SectionTitle(text: "Pendientes")
            NavigationLink {
                MockOrdersView()
            } label: {
                MockRow(title: "Resultados por revisar", detail: "2 pendientes, 1 crítico", tag: "Crítico", alert: true)
            }
            .buttonStyle(.plain)
            if FlowVisibility.showsStartConsultation(user.access) {
                NavigationLink {
                    MockConsultaView()
                } label: {
                    MockRow(title: "Iniciar consulta", detail: "Ana Ficticia · B-017", tag: "Siguiente")
                }
                .buttonStyle(.plain)
            }
            if FlowVisibility.showsHospitalized(user.access) {
                NavigationLink {
                    MockHospitalizadosView()
                } label: {
                    MockRow(title: "Mis hospitalizados", detail: "3 pacientes ficticios", tag: "Hoy")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Órdenes y resultados: cola con crítico arriba en rojo.
struct MockOrdersView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / MEDICINA", title: "Órdenes y resultados.", titleSize: 26) {
            MockNotice()
            ForEach(mockExamSamples) { exam in
                NavigationLink {
                    MockResultadoView(exam: exam, patientView: false)
                } label: {
                    MockRow(title: exam.name,
                            detail: "Paciente ficticio · Orden MED-2026-0042",
                            tag: exam.reviewed ? "Revisado" : "Por revisar",
                            alert: exam.critical)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Consulta: motivo, diagnóstico, plan y acciones de maqueta (no guarda ni firma).
struct MockConsultaView: View {
    @State var reason: String = ""
    @State var diagnosis: String = ""
    @State var plan: String = ""
    @State var message: String? = nil

    var body: some View {
        ScreenScaffold(label: "MAQUETA / MEDICINA", title: "Consulta.", titleSize: 28) {
            MockNotice()
            Card {
                DetailRow(label: "Paciente", value: "Ana Ficticia · B-017")
                DetailRow(label: "Signos de asistencia", value: "PA 120/80 · FC 72 · T 36.8 °C (ficticios)")
            }
            PlainField(label: "Motivo de consulta", text: $reason, prompt: "Motivo", axis: .vertical)
            PlainField(label: "Diagnóstico (buscador CIE-10)", text: $diagnosis, prompt: "Escribe un término")
            PlainField(label: "Plan y receta", text: $plan, prompt: "Indicaciones", axis: .vertical)
            SecondaryButton(title: "Ordenar laboratorio") {
                message = "Maqueta: la orden no se envió."
            }
            SecondaryButton(title: "Guardar borrador") {
                message = "Maqueta: nada se guardó."
            }
            BodyText(text: "Firmar exige inscripción profesional vigente.")
            PrimaryButton(title: "Firmar consulta") {
                message = "Maqueta: la consulta no se firmó."
            }
            if let message = message {
                Banner(kind: .info, text: message)
            }
        }
    }
}

/// Mis hospitalizados: cama, días y estado.
struct MockHospitalizadosView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / MEDICINA", title: "Hospitalizados.", titleSize: 28) {
            MockNotice()
            MockRow(title: "Luis Demo · Cama 2-03", detail: "4 días · Medicina interna", tag: "Alta pendiente")
            MockRow(title: "Ana Ficticia · Cama 3-VIP-1", detail: "1 día · Cirugía", tag: "Estable")
            MockRow(title: "Carlos Prueba · Cama 2-11", detail: "9 días · Falta resultado de laboratorio", tag: "Observación")
        }
    }
}

// MARK: - Maquetas de vinculación, cuenta, expediente y llegada (I03, I10, I11, I13, I22, I25)

/// Estados de la vinculación que la maqueta puede simular.
enum MockLinkState: String, CaseIterable {
    case enVerificacion = "En verificación"
    case aprobada = "Aprobada"
    case rechazada = "Rechazada"
}

/// Vincular cuenta con expediente: DUI y fecha de nacimiento, con un estado simulado.
struct MockVinculacionView: View {
    @State var dui: String = ""
    @State var birthDate: String = ""
    @State var simulated: MockLinkState = .enVerificacion

    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Vincular expediente.", titleSize: 28) {
            MockNotice()
            BodyText(text: "Une tu cuenta con tu expediente. Mientras no se apruebe, no verás datos clínicos.")
            PlainField(label: "DUI", text: $dui, prompt: "00000000-0")
            PlainField(label: "Fecha de nacimiento", text: $birthDate, prompt: "DD/MM/AAAA")
            PrimaryButton(title: "Enviar", isEnabled: false) {}
            SectionTitle(text: "Estado (simulado)")
            Picker("Estado", selection: $simulated) {
                ForEach(MockLinkState.allCases, id: \.self) { state in
                    Text(state.rawValue).tag(state)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.blue)
            MockRow(title: simulated.rawValue,
                    detail: "Solo cambia en esta maqueta. La aprobación la hace el personal de recepción.",
                    tag: simulated == .rechazada ? "Rechazada" : nil,
                    alert: simulated == .rechazada)
        }
    }
}

/// Información pública del hospital: ocupación general, médicos de turno y avisos. Sin nombres de pacientes.
struct MockHospitalInfoView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / PÚBLICO", title: "Hospital.", titleSize: 30) {
            MockNotice()
            SectionTitle(text: "Ocupación general")
            MockRow(title: "2.ª planta", detail: "8 de 12 camas ocupadas (ficticio)", tag: "Ocupada")
            MockRow(title: "3.ª planta", detail: "3 de 5 habitaciones VIP ocupadas (ficticio)", tag: "Disponible")
            SectionTitle(text: "Médicos de turno")
            MockRow(title: "Dra. Ejemplo Prueba", detail: "Medicina interna · hasta las 18:00")
            SectionTitle(text: "Avisos")
            MockRow(title: "Elevador en mantenimiento", detail: "Usa la escalera norte hasta el viernes (ficticio)")
            BodyText(text: "Información pública: no muestra datos de pacientes.")
        }
    }
}

/// Quién vio mi expediente: cada acceso con fecha, rol y motivo. Solo lectura.
struct MockAccesosView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Quién vio mi expediente.", titleSize: 26) {
            MockNotice()
            BodyText(text: "Cada vez que alguien abre tu expediente queda registrado aquí.")
            MockRow(title: "12/10/2026 · 09:14", detail: "Dra. Ejemplo Prueba · Médica tratante · Consulta programada")
            MockRow(title: "03/08/2026 · 16:40", detail: "Dr. Ficticio Demo · Acceso excepcional aprobado", tag: "Excepción")
            BodyText(text: "Los accesos no se pueden borrar desde la app.")
        }
    }
}

/// Mi cuenta: cargos, pagos y factura propia. Sin contenido clínico.
struct MockCuentaView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / PACIENTE", title: "Mi cuenta.", titleSize: 30) {
            MockNotice()
            Card {
                DetailRow(label: "Saldo pendiente", value: "$0.00 (ficticio)")
                DetailRow(label: "Último pago", value: "$25.00 · 10/10/2026 (ficticio)")
            }
            SectionTitle(text: "Cargos")
            MockRow(title: "Consulta general", detail: "12/10/2026 · $25.00", tag: "Pagado")
            MockRow(title: "Laboratorio", detail: "12/10/2026 · $18.50", tag: "Pagado")
            SecondaryButton(title: "Descargar factura", isEnabled: false) {}
            BodyText(text: "Solo ves tu propia cuenta. Ningún dato económico llega al personal clínico.")
        }
    }
}

/// Tipos de registro del expediente, en pestañas internas.
enum MockRecordSection: String, CaseIterable {
    case consultas = "Consultas"
    case diagnosticos = "Diagnósticos"
    case recetas = "Recetas"
    case resultados = "Resultados"
    case hospitalizaciones = "Hospitalizaciones"
}

/// Expediente del paciente (médico): historial por secciones. Todo acceso queda auditado.
struct MockExpedienteView: View {
    @State var section: MockRecordSection = .consultas

    var body: some View {
        ScreenScaffold(label: "MAQUETA / MEDICINA", title: "Expediente.", titleSize: 30) {
            MockNotice()
            Card {
                DetailRow(label: "Paciente", value: "Ana Ficticia · expediente de prueba")
                DetailRow(label: "Acceso", value: "Auditado: queda registrado con tu nombre y la hora.")
            }
            Picker("Sección", selection: $section) {
                ForEach(MockRecordSection.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.blue)
            SectionTitle(text: section.rawValue)
            sectionRows
            SecondaryButton(title: "Pedir acceso excepcional", isEnabled: false) {}
            BodyText(text: "Si no eres la médica o el médico tratante, el acceso lo aprueba otra persona.")
        }
    }

    @ViewBuilder
    private var sectionRows: some View {
        switch section {
        case .consultas:
            MockRow(title: "12/10/2026 · Dra. Ejemplo Prueba", detail: "Faringitis aguda (ficticio)")
            MockRow(title: "03/08/2026 · Dr. Ficticio Demo", detail: "Control de presión arterial (ficticio)")
        case .diagnosticos:
            MockRow(title: "J02.9 · Faringitis aguda", detail: "Diagnóstico activo (ficticio)")
            MockRow(title: "I10 · Hipertensión esencial", detail: "Control en curso (ficticio)")
        case .recetas:
            MockRow(title: "Paracetamol 500 mg", detail: "Cada 8 horas durante 3 días (ficticio)")
        case .resultados:
            ForEach(mockExamSamples) { exam in
                MockRow(title: exam.name, detail: "Resultado de prueba", tag: exam.state, alert: exam.critical)
            }
        case .hospitalizaciones:
            MockRow(title: "Cama 2-03 · Medicina interna", detail: "4 días (ficticio)", tag: "Alta pendiente")
        }
    }
}

/// Llegada de ambulancia: reporte prehospital para quien recibe al paciente. Solo lectura.
struct MockLlegadaView: View {
    var body: some View {
        ScreenScaffold(label: "MAQUETA / MEDICINA", title: "Llegada de ambulancia.", titleSize: 26) {
            MockNotice()
            Banner(kind: .info, text: "Datos prehospitalarios: solo para quien recibe al paciente.")
            Card {
                DetailRow(label: "Hora estimada de llegada", value: "14:20 (ficticia)")
                DetailRow(label: "Motivo", value: "Dolor torácico (ficticio)")
                DetailRow(label: "Signos", value: "FC 110 · PA 150/95 · SatO2 94 % (ficticios)")
                DetailRow(label: "Prioridad", value: "Alta")
            }
            PrimaryButton(title: "Marcar recibido", isEnabled: false) {}
        }
    }
}