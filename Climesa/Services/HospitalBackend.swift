import Foundation
import CryptoKit

enum Crypto {
    static func hash(_ password: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt.lowercased() + ":" + password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Datos iniciales (demo)

enum SeedData {
    static func make() -> HospitalData {
        func user(_ name: String, _ email: String, _ pass: String, _ role: Role) -> User {
            User(name: name, email: email, passwordHash: Crypto.hash(pass, salt: email), role: role)
        }
        let admin = user("Marcela Quintanilla", "admin@climesa.com", "Admin123!", .administrador)
        let doctor = user("Dr. Ana Morales", "doctor@climesa.com", "Doctor123!", .doctor)
        let doctor2 = user("Dr. Carlos Rivas", "doctor2@climesa.com", "Doctor123!", .doctor)
        let recep = user("Rosa Menjívar", "recepcion@climesa.com", "Recep123!", .recepcionista)
        let asis = user("Jorge Alas", "asistente@climesa.com", "Asist123!", .asistente)
        let p1 = user("Mario Cañas", "paciente@climesa.com", "Paciente123!", .paciente)
        let p2 = user("Marta Gómez", "marta@climesa.com", "Paciente123!", .paciente)
        let p3 = user("Luis Hernández", "luis@climesa.com", "Paciente123!", .paciente)
        let p4 = user("Carla Ríos", "carla@climesa.com", "Paciente123!", .paciente)
        // Cuentas de las vistas "Medicina" y "Paciente" del diseño.
        let med = user("Ana Isabel Ejemplo", "med@example.test", "Medico123!", .doctor)
        let pac = user("Ana Lucía Ejemplo", "pac@example.test", "Paciente123!", .paciente)
        var medpac = user("Ana Isabel Ejemplo", "medpac@example.test", "Medico123!", .doctor)
        medpac.extraAreas = [.pac]   // cuenta con ambos roles (selector Medicina / Paciente)

        // 3ª planta: VIP-301…305 (1 cama) · 2ª planta: HAB-201…206 (2 camas) = 12 camas semiprivadas + 5 VIP
        var rooms: [Room] = (1...5).map { Room(id: "VIP-30\($0)", floor: 3, kind: .vip, occupantIds: []) }
        rooms += (1...6).map { Room(id: "HAB-20\($0)", floor: 2, kind: .semiprivada, occupantIds: []) }
        rooms[1].occupantIds = [p2.id]   // VIP-302
        rooms[5].occupantIds = [p3.id]   // HAB-201

        let now = Date()
        let day: TimeInterval = 86_400
        let labs = [
            LabOrder(patientId: p1.id, doctorId: doctor.id, exam: "Hemograma completo", status: .completado,
                     result: "Valores dentro de rangos normales.", createdAt: now - 3 * day),
            LabOrder(patientId: p1.id, doctorId: doctor.id, exam: "Perfil lipídico", status: .enProceso,
                     result: nil, createdAt: now - 1 * day),
            LabOrder(patientId: p2.id, doctorId: doctor.id, exam: "Glucosa en ayunas", status: .pendiente,
                     result: nil, createdAt: now - 2 * 3600)
        ]
        let consultations = [
            Consultation(patientId: p1.id, doctorId: doctor.id,
                         diagnosis: "Hipertensión leve. Control en 30 días.",
                         prescription: "Losartán 50 mg, una tableta al día.", date: now - 3 * day),
            Consultation(patientId: p2.id, doctorId: doctor.id,
                         diagnosis: "Recuperación postoperatoria estable.",
                         prescription: "Paracetamol 500 mg cada 8 horas por 3 días.", date: now - 1 * day)
        ]

        var shifts: [Shift] = []
        for d in 0..<7 {
            shifts.append(Shift(staffName: "Dr. Ana Morales", title: .doctor, weekday: d, startMinutes: 7 * 60, endMinutes: 15 * 60))
            shifts.append(Shift(staffName: "Dr. Carlos Rivas", title: .doctor, weekday: d, startMinutes: 15 * 60, endMinutes: 23 * 60))
            shifts.append(Shift(staffName: "Dra. Lucía Fuentes", title: .doctor, weekday: d, startMinutes: 23 * 60, endMinutes: 7 * 60))
        }
        for d in 0..<5 {
            shifts.append(Shift(staffName: "Patricia Gil", title: .enfermera, weekday: d, startMinutes: 7 * 60, endMinutes: 19 * 60))
            shifts.append(Shift(staffName: "Jorge Alas", title: .asistente, weekday: d, startMinutes: 7 * 60, endMinutes: 15 * 60))
        }
        for d in 0..<6 {
            shifts.append(Shift(staffName: "Rosa Menjívar", title: .recepcionista, weekday: d, startMinutes: 7 * 60, endMinutes: 15 * 60))
        }
        for d in [0, 2] {
            shifts.append(Shift(staffName: "Dr. Hugo Pineda", title: .alergista, weekday: d, startMinutes: 9 * 60, endMinutes: 13 * 60))
        }
        for d in [5, 6] {
            shifts.append(Shift(staffName: "Dr. Iván Ortiz", title: .emergencia, weekday: d, startMinutes: 19 * 60, endMinutes: 7 * 60))
        }
        // Turnos publicados de la cuenta med@example.test (sábado, lunes y miércoles 7:00–15:00).
        // medpac@example.test no tiene turnos a propósito: muestra el estado vacío.
        for d in [5, 0, 2] {
            shifts.append(Shift(staffName: "Ana Isabel Ejemplo", title: .doctor, weekday: d,
                                startMinutes: 7 * 60, endMinutes: 15 * 60, userId: med.id))
        }

        let log = [
            AmbulanceLogEntry(requestedBy: "Rosa Menjívar", reason: "Traslado a hemodiálisis",
                              destination: "Hospital Nacional", dispatchedBy: "Rosa Menjívar",
                              startedAt: now - 2 * day, endedAt: now - 2 * day + 5400)
        ]

        return HospitalData(
            users: [admin, doctor, doctor2, recep, asis, p1, p2, p3, p4, med, pac, medpac],
            rooms: rooms, labs: labs, consultations: consultations, shifts: shifts,
            ambulanceState: .disponible, ambulancePending: nil, ambulanceLog: log,
            notices: ["Horario de visitas: 2:00 p. m. a 6:00 p. m.",
                      "Campaña de vacunación en consulta general esta semana."]
        )
    }
}

// MARK: - Backend local (actor = acceso serializado, sin condiciones de carrera)

/// Simula la API del hospital. Cada método aplica las reglas de negocio y el control
/// de acceso por rol (RBAC) del lado "servidor". Para pasar a un backend real, mantén
/// esta superficie y reemplaza la implementación por llamadas URLSession.
actor HospitalBackend {
    static let shared = HospitalBackend()

    /// Demo: las cuentas nuevas quedan activas sin enlace por correo.
    static let autoActivateAccounts = true

    private var data: HospitalData
    private static let storageKey = "climesa.data.v2"

    /// Interruptor de depuración (Mi cuenta → "Simular sin conexión") o argumento `-simulateOffline`.
    static let offlineKey = "climesa.debug.offline"

    init() {
        if let raw = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(HospitalData.self, from: raw) {
            data = decoded
        } else {
            let seed = SeedData.make()
            data = seed
            if let raw = try? JSONEncoder().encode(seed) {
                UserDefaults.standard.set(raw, forKey: Self.storageKey)
            }
        }
    }

    // MARK: Infraestructura interna

    private func persist() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: Self.storageKey)
        }
    }

    private func simulateLatency(_ milliseconds: UInt64 = 350) async throws {
        if ProcessInfo.processInfo.arguments.contains("-simulateOffline")
            || UserDefaults.standard.bool(forKey: Self.offlineKey) {
            try await Task.sleep(nanoseconds: 300_000_000)
            throw BackendError.network
        }
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private func require(_ user: UserProfile, _ roles: [Role]) throws {
        guard roles.contains(user.role) else { throw BackendError.forbidden }
    }

    private func name(of id: UUID) -> String {
        data.users.first { $0.id == id }?.name ?? "—"
    }

    private func roomId(of patientId: UUID) -> String? {
        data.rooms.first { $0.occupantIds.contains(patientId) }?.id
    }

    /// Política de privacidad: quién puede ver datos protegidos de un paciente.
    private func canSeePatient(_ user: UserProfile, _ patientId: UUID) -> Bool {
        switch user.role {
        case .administrador, .recepcionista, .asistente: return true
        case .doctor:
            return data.consultations.contains { $0.doctorId == user.id && $0.patientId == patientId }
                || data.labs.contains { $0.doctorId == user.id && $0.patientId == patientId }
        case .paciente: return user.id == patientId
        }
    }

    // MARK: Autenticación

    func register(name: String, email: String, password: String) async throws {
        try await simulateLatency(900)
        let email = email.trimmed.lowercased()
        guard !data.users.contains(where: { $0.email == email }) else { throw BackendError.emailTaken }
        data.users.append(User(name: name.trimmed, email: email,
                               passwordHash: Crypto.hash(password, salt: email),
                               role: .paciente, isActive: Self.autoActivateAccounts))
        persist()
    }

    func login(email: String, password: String) async throws -> UserProfile {
        try await simulateLatency(1100)
        let email = email.trimmed.lowercased()
        guard let user = data.users.first(where: { $0.email == email }),
              user.passwordHash == Crypto.hash(password, salt: email),
              user.isActive else { throw BackendError.invalidCredentials }
        return user.profile
    }

    func validateSession(userId: UUID) async throws -> UserProfile? {
        try await simulateLatency(900)
        return data.users.first { $0.id == userId && $0.isActive }?.profile
    }

    // MARK: Información pública

    func publicOverview() -> PublicOverview {
        let total = data.rooms.reduce(0) { $0 + $1.kind.capacity }
        let occupied = data.rooms.reduce(0) { $0 + $1.occupantIds.count }
        let vipFree = data.rooms.filter { $0.kind == .vip && $0.occupantIds.isEmpty }.count
        let semiFree = data.rooms.filter { $0.kind == .semiprivada }
            .reduce(0) { $0 + ($1.kind.capacity - $1.occupantIds.count) }
        let now = Date()
        let doctors = data.shifts.filter { $0.title == .doctor && $0.isOnDuty(at: now) }.map(\.staffName)
        return PublicOverview(totalBeds: total, occupiedBeds: occupied, vipFree: vipFree,
                              semiBedsFree: semiFree, onDutyDoctors: doctors, notices: data.notices)
    }

    // MARK: Pacientes

    func patients(for user: UserProfile) throws -> [PatientSummary] {
        try require(user, [.administrador, .doctor, .recepcionista, .asistente])
        return data.users.filter { $0.role == .paciente && $0.isActive }
            .sorted { $0.name < $1.name }
            .map { PatientSummary(id: $0.id, name: $0.name, email: $0.email,
                                  roomId: canSeePatient(user, $0.id) ? roomId(of: $0.id) : nil) }
    }

    // MARK: Habitaciones

    func rooms(for user: UserProfile) -> [RoomInfo] {
        data.rooms
            .filter { user.role != .paciente || $0.occupantIds.contains(user.id) }
            .map { room in
                RoomInfo(id: room.id, floor: room.floor, kind: room.kind,
                         occupants: room.occupantIds.map { pid in
                             OccupantInfo(patientId: pid, name: canSeePatient(user, pid) ? name(of: pid) : nil)
                         })
            }
    }

    func assign(patientId: UUID, roomId: String, by user: UserProfile) async throws {
        try require(user, [.administrador, .recepcionista, .asistente])
        try await simulateLatency()
        // Validaciones DESPUÉS del await: el actor garantiza que nadie más modifica el estado entre check y write.
        guard data.users.contains(where: { $0.id == patientId && $0.role == .paciente }) else { throw BackendError.notFound }
        guard self.roomId(of: patientId) == nil else {
            throw BackendError.validation("El paciente ya tiene una cama asignada.")
        }
        guard let i = data.rooms.firstIndex(where: { $0.id == roomId }) else { throw BackendError.notFound }
        guard data.rooms[i].occupantIds.count < data.rooms[i].kind.capacity else {
            throw BackendError.validation("La habitación está completa. No se permite sobrecupo.")
        }
        data.rooms[i].occupantIds.append(patientId)
        persist()
    }

    /// Algoritmo de asignación: VIP → primera libre. Semiprivada → completa primero las habitaciones con 1 ocupante.
    func autoAssign(patientId: UUID, kind: RoomKind, by user: UserProfile) async throws -> String {
        try require(user, [.administrador, .recepcionista, .asistente])
        try await simulateLatency()
        guard data.users.contains(where: { $0.id == patientId && $0.role == .paciente }) else { throw BackendError.notFound }
        guard roomId(of: patientId) == nil else {
            throw BackendError.validation("El paciente ya tiene una cama asignada.")
        }
        let candidates = data.rooms.indices.filter {
            data.rooms[$0].kind == kind && data.rooms[$0].occupantIds.count < kind.capacity
        }
        let ordered = candidates.sorted { a, b in
            let ca = data.rooms[a].occupantIds.count, cb = data.rooms[b].occupantIds.count
            return ca != cb ? ca > cb : a < b
        }
        guard let index = ordered.first else {
            throw BackendError.validation(kind == .vip ? "No hay habitaciones VIP libres." : "No hay camas semiprivadas libres.")
        }
        data.rooms[index].occupantIds.append(patientId)
        persist()
        return data.rooms[index].id
    }

    func discharge(patientId: UUID, by user: UserProfile) async throws {
        try require(user, [.administrador, .recepcionista, .asistente])
        try await simulateLatency()
        guard let i = data.rooms.firstIndex(where: { $0.occupantIds.contains(patientId) }) else { throw BackendError.notFound }
        data.rooms[i].occupantIds.removeAll { $0 == patientId }
        persist()
    }

    // MARK: Laboratorio

    func labs(for user: UserProfile) throws -> [LabInfo] {
        let list: [LabOrder]
        switch user.role {
        case .paciente: list = data.labs.filter { $0.patientId == user.id }
        case .doctor: list = data.labs.filter { $0.doctorId == user.id }
        case .administrador, .asistente: list = data.labs
        case .recepcionista: throw BackendError.forbidden
        }
        return list.sorted { $0.createdAt > $1.createdAt }
            .map { LabInfo(order: $0, patientName: name(of: $0.patientId), doctorName: name(of: $0.doctorId)) }
    }

    func createLab(patientId: UUID, exam: String, by user: UserProfile) async throws {
        try require(user, [.doctor])
        try await simulateLatency()
        guard !exam.trimmed.isEmpty else { throw BackendError.validation("Escribe el examen solicitado.") }
        guard data.users.contains(where: { $0.id == patientId && $0.role == .paciente }) else { throw BackendError.notFound }
        data.labs.append(LabOrder(patientId: patientId, doctorId: user.id, exam: exam.trimmed,
                                  status: .pendiente, result: nil, createdAt: Date()))
        persist()
    }

    func advanceLab(id: UUID, result: String?, by user: UserProfile) async throws {
        try require(user, [.administrador, .asistente, .doctor])
        try await simulateLatency()
        guard let i = data.labs.firstIndex(where: { $0.id == id }) else { throw BackendError.notFound }
        if user.role == .doctor && data.labs[i].doctorId != user.id { throw BackendError.forbidden }
        switch data.labs[i].status {
        case .pendiente:
            data.labs[i].status = .enProceso
        case .enProceso:
            let r = (result ?? "").trimmed
            guard !r.isEmpty else { throw BackendError.validation("Escribe el resultado para completar el examen.") }
            data.labs[i].result = r
            data.labs[i].status = .completado
        case .completado:
            break
        }
        persist()
    }

    // MARK: Consulta general

    func consultations(for user: UserProfile) throws -> [ConsultationInfo] {
        let list: [Consultation]
        switch user.role {
        case .paciente: list = data.consultations.filter { $0.patientId == user.id }
        case .doctor: list = data.consultations.filter { $0.doctorId == user.id }
        case .administrador: list = data.consultations
        case .recepcionista, .asistente: throw BackendError.forbidden
        }
        return list.sorted { $0.date > $1.date }
            .map { ConsultationInfo(consultation: $0, patientName: name(of: $0.patientId), doctorName: name(of: $0.doctorId)) }
    }

    func createConsultation(patientId: UUID, diagnosis: String, prescription: String,
                            exams: [String], by user: UserProfile) async throws {
        try require(user, [.doctor])
        try await simulateLatency()
        guard !diagnosis.trimmed.isEmpty else { throw BackendError.validation("Escribe el diagnóstico.") }
        guard data.users.contains(where: { $0.id == patientId && $0.role == .paciente }) else { throw BackendError.notFound }
        let now = Date()
        data.consultations.append(Consultation(patientId: patientId, doctorId: user.id,
                                               diagnosis: diagnosis.trimmed, prescription: prescription.trimmed, date: now))
        for exam in exams.map(\.trimmed) where !exam.isEmpty {
            data.labs.append(LabOrder(patientId: patientId, doctorId: user.id, exam: exam,
                                      status: .pendiente, result: nil, createdAt: now))
        }
        persist()
    }

    // MARK: Turnos

    func shifts(for user: UserProfile) -> [Shift] {
        let all = data.shifts
        // Información pública para pacientes: solo médicos de turno.
        return user.role == .paciente ? all.filter { $0.title == .doctor } : all
    }

    /// "Mis turnos": próximas ocurrencias (7 días) de los turnos publicados de la cuenta.
    func myShifts(for user: UserProfile) async throws -> [ShiftOccurrence] {
        try await simulateLatency(900)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let now = Date()
        var result: [ShiftOccurrence] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = (cal.component(.weekday, from: day) + 5) % 7
            for s in data.shifts where s.published && s.weekday == weekday
                && (s.userId == user.id || (s.userId == nil && s.staffName == user.name)) {
                let endMinutes = s.endMinutes > s.startMinutes ? s.endMinutes : s.endMinutes + 24 * 60
                guard let start = cal.date(byAdding: .minute, value: s.startMinutes, to: day),
                      let end = cal.date(byAdding: .minute, value: endMinutes, to: day),
                      end > now else { continue }
                result.append(ShiftOccurrence(id: "\(s.id.uuidString)-\(offset)", service: s.service,
                                              start: start, end: end, published: s.published))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    func addShift(staffName: String, title: StaffTitle, weekday: Int,
                  start: Int, end: Int, by user: UserProfile) async throws {
        try require(user, [.administrador])
        try await simulateLatency()
        guard !staffName.trimmed.isEmpty else { throw BackendError.validation("Escribe el nombre del personal.") }
        guard start != end else { throw BackendError.validation("La hora de inicio y fin no pueden ser iguales.") }
        data.shifts.append(Shift(staffName: staffName.trimmed, title: title, weekday: weekday,
                                 startMinutes: start, endMinutes: end))
        persist()
    }

    func removeShift(id: UUID, by user: UserProfile) async throws {
        try require(user, [.administrador])
        data.shifts.removeAll { $0.id == id }
        persist()
    }

    // MARK: Ambulancia (única)

    func ambulance(for user: UserProfile) -> AmbulanceSnapshot {
        var snap = AmbulanceSnapshot(state: data.ambulanceState,
                                     pending: data.ambulancePending,
                                     active: data.ambulanceLog.first { $0.endedAt == nil })
        if user.role == .paciente {
            if snap.pending?.patientId != user.id { snap.pending = nil }
            snap.active = nil   // bitácora y servicio activo: información privada
        }
        return snap
    }

    private func startService(requestedBy: String, reason: String, destination: String, dispatchedBy: String) {
        data.ambulanceLog.insert(AmbulanceLogEntry(requestedBy: requestedBy, reason: reason, destination: destination,
                                                   dispatchedBy: dispatchedBy, startedAt: Date(), endedAt: nil), at: 0)
        data.ambulanceState = .enServicio
    }

    /// Paciente → crea solicitud pendiente. Personal → despacha directamente.
    func requestAmbulance(reason: String, destination: String, by user: UserProfile) async throws {
        try await simulateLatency()
        guard !reason.trimmed.isEmpty else { throw BackendError.validation("Indica el motivo de la emergencia.") }
        guard data.ambulanceState != .enMantenimiento else { throw BackendError.validation("La ambulancia está en mantenimiento.") }
        guard data.ambulanceState == .disponible else { throw BackendError.validation("La ambulancia está en servicio. Intenta más tarde.") }
        guard data.ambulancePending == nil else { throw BackendError.validation("Ya existe una solicitud pendiente.") }
        if user.role == .paciente {
            data.ambulancePending = AmbulanceRequest(patientId: user.id, patientName: user.name, reason: reason.trimmed,
                                                     destination: destination.trimmed, createdAt: Date())
        } else {
            startService(requestedBy: user.name, reason: reason.trimmed, destination: destination.trimmed, dispatchedBy: user.name)
        }
        persist()
    }

    func dispatchPending(by user: UserProfile) async throws {
        try require(user, [.administrador, .recepcionista, .asistente, .doctor])
        try await simulateLatency()
        guard let pending = data.ambulancePending else { throw BackendError.notFound }
        guard data.ambulanceState == .disponible else { throw BackendError.validation("La ambulancia no está disponible.") }
        startService(requestedBy: pending.patientName, reason: pending.reason,
                     destination: pending.destination, dispatchedBy: user.name)
        data.ambulancePending = nil
        persist()
    }

    func cancelPending(by user: UserProfile) async throws {
        try await simulateLatency()
        guard let pending = data.ambulancePending else { return }
        if user.role == .paciente && pending.patientId != user.id { throw BackendError.forbidden }
        data.ambulancePending = nil
        persist()
    }

    func finishService(by user: UserProfile) async throws {
        try require(user, [.administrador, .recepcionista, .asistente, .doctor])
        try await simulateLatency()
        guard let i = data.ambulanceLog.firstIndex(where: { $0.endedAt == nil }) else {
            throw BackendError.validation("No hay un servicio activo.")
        }
        data.ambulanceLog[i].endedAt = Date()
        data.ambulanceState = .disponible
        persist()
    }

    func setMaintenance(_ on: Bool, by user: UserProfile) async throws {
        try require(user, [.administrador])
        try await simulateLatency()
        if on {
            guard data.ambulanceState == .disponible else {
                throw BackendError.validation("Finaliza el servicio activo antes de enviarla a mantenimiento.")
            }
            data.ambulancePending = nil
            data.ambulanceState = .enMantenimiento
        } else if data.ambulanceState == .enMantenimiento {
            data.ambulanceState = .disponible
        }
        persist()
    }

    func ambulanceLog(for user: UserProfile, since: Date?) throws -> [AmbulanceLogEntry] {
        try require(user, [.administrador, .doctor, .recepcionista, .asistente])
        return data.ambulanceLog
            .filter { since == nil || $0.startedAt >= since! }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
