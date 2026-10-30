import Foundation

// MARK: - Utilidades

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Usuarios y roles

enum Role: String, Codable, CaseIterable, Identifiable {
    case administrador, doctor, recepcionista, asistente, paciente
    var id: String { rawValue }

    var title: String {
        switch self {
        case .administrador: return "Administrador"
        case .doctor: return "Doctor"
        case .recepcionista: return "Recepcionista"
        case .asistente: return "Asistente"
        case .paciente: return "Paciente"
        }
    }
    var isStaff: Bool { self != .paciente }
}

/// Áreas de la app con diseño propio (shell con barra inferior): Medicina y Paciente.
enum Area: String, Codable, CaseIterable, Identifiable {
    case med = "MED", pac = "PAC"
    var id: String { rawValue }
    var code: String { rawValue }
    var title: String { self == .med ? "Medicina" : "Paciente" }
}

struct User: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var email: String
    var passwordHash: String
    var role: Role
    var isActive = true
    /// Áreas adicionales a la que da el rol (p. ej. un médico que también es paciente).
    var extraAreas: [Area] = []

    var areas: [Area] {
        var list: [Area] = []
        switch role {
        case .doctor: list = [.med]
        case .paciente: list = [.pac]
        default: break
        }
        for a in extraAreas where !list.contains(a) { list.append(a) }
        return list
    }

    var profile: UserProfile { UserProfile(id: id, name: name, email: email, role: role, areas: areas) }
}

/// Lo único que la app conoce de la sesión (nunca el hash).
struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let email: String
    let role: Role
    let areas: [Area]

    /// Doctor y paciente usan el shell de las nuevas vistas; el resto de roles, el panel operativo.
    var usesShell: Bool { !areas.isEmpty }

    var firstName: String {
        let parts = name.split(separator: " ").map(String.init)
        if let first = parts.first, first.hasSuffix("."), parts.count > 1 { return parts[1] }
        return parts.first ?? name
    }
}

struct PatientSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let email: String
    let roomId: String?
}

// MARK: - Habitaciones

enum RoomKind: String, Codable, CaseIterable {
    case vip, semiprivada
    var capacity: Int { self == .vip ? 1 : 2 }
    var title: String { self == .vip ? "VIP · Individual" : "Semiprivada · 2 camas" }
}

struct Room: Identifiable, Codable, Hashable {
    var id: String
    var floor: Int
    var kind: RoomKind
    var occupantIds: [UUID]
}

struct OccupantInfo: Identifiable, Hashable {
    var id: UUID { patientId }
    let patientId: UUID
    /// nil = dato protegido para quien consulta.
    let name: String?
}

struct RoomInfo: Identifiable, Hashable {
    let id: String
    let floor: Int
    let kind: RoomKind
    let occupants: [OccupantInfo]
    var capacity: Int { kind.capacity }
    var isFull: Bool { occupants.count >= capacity }
}

// MARK: - Laboratorio y consulta

enum LabStatus: String, Codable {
    case pendiente, enProceso, completado
    var title: String {
        switch self {
        case .pendiente: return "Pendiente"
        case .enProceso: return "En proceso"
        case .completado: return "Completado"
        }
    }
}

struct LabOrder: Identifiable, Codable, Hashable {
    var id = UUID()
    var patientId: UUID
    var doctorId: UUID
    var exam: String
    var status: LabStatus
    var result: String?
    var createdAt: Date
}

struct LabInfo: Identifiable, Hashable {
    var id: UUID { order.id }
    let order: LabOrder
    let patientName: String
    let doctorName: String
}

struct Consultation: Identifiable, Codable, Hashable {
    var id = UUID()
    var patientId: UUID
    var doctorId: UUID
    var diagnosis: String
    var prescription: String
    var date: Date
}

struct ConsultationInfo: Identifiable, Hashable {
    var id: UUID { consultation.id }
    let consultation: Consultation
    let patientName: String
    let doctorName: String
}

// MARK: - Turnos

enum StaffTitle: String, Codable, CaseIterable, Identifiable {
    case doctor, enfermera, alergista, emergencia, asistente, recepcionista
    var id: String { rawValue }
    var title: String {
        switch self {
        case .doctor: return "Doctor"
        case .enfermera: return "Enfermera"
        case .alergista: return "Alergista"
        case .emergencia: return "Emergencia"
        case .asistente: return "Asistente"
        case .recepcionista: return "Recepcionista"
        }
    }
}

struct Shift: Identifiable, Codable, Hashable {
    var id = UUID()
    var staffName: String
    var title: StaffTitle
    /// 0 = lunes … 6 = domingo
    var weekday: Int
    var startMinutes: Int
    var endMinutes: Int
    /// Nombre del servicio que se muestra en "Mis turnos".
    var service: String = "Consulta general"
    var published: Bool = true
    /// Si existe, el turno pertenece a esa cuenta; si no, se asocia por nombre.
    var userId: UUID? = nil

    static let weekdayNames = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

    static func format(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
    var range: String { "\(Shift.format(startMinutes)) – \(Shift.format(endMinutes))" }

    func isOnDuty(at date: Date) -> Bool {
        let cal = Calendar.current
        let wd = (cal.component(.weekday, from: date) + 5) % 7
        let now = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        if startMinutes < endMinutes {
            return wd == weekday && now >= startMinutes && now < endMinutes
        }
        return (wd == weekday && now >= startMinutes) || (wd == (weekday + 1) % 7 && now < endMinutes)
    }
}

/// Ocurrencia concreta (fecha y hora) de un turno semanal publicado.
struct ShiftOccurrence: Identifiable, Hashable {
    let id: String
    let service: String
    let start: Date
    let end: Date
    let published: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d 'de' MMMM 'de' yyyy, h:mm a"
        return f
    }()

    var startText: String { Self.formatter.string(from: start) }
    var endText: String { "Hasta " + Self.formatter.string(from: end) }
}

// MARK: - Ambulancia (recurso único)

enum AmbulanceState: String, Codable {
    case disponible, enServicio, enMantenimiento
    var title: String {
        switch self {
        case .disponible: return "Disponible"
        case .enServicio: return "En servicio"
        case .enMantenimiento: return "En mantenimiento"
        }
    }
}

struct AmbulanceRequest: Identifiable, Codable, Hashable {
    var id = UUID()
    var patientId: UUID
    var patientName: String
    var reason: String
    var destination: String
    var createdAt: Date
}

struct AmbulanceLogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var requestedBy: String
    var reason: String
    var destination: String
    var dispatchedBy: String
    var startedAt: Date
    var endedAt: Date?
}

struct AmbulanceSnapshot: Hashable {
    var state: AmbulanceState
    var pending: AmbulanceRequest?
    var active: AmbulanceLogEntry?
}

// MARK: - Información pública

struct PublicOverview {
    let totalBeds: Int
    let occupiedBeds: Int
    let vipFree: Int
    let semiBedsFree: Int
    let onDutyDoctors: [String]
    let notices: [String]
}

// MARK: - Persistencia y errores

struct HospitalData: Codable {
    var users: [User]
    var rooms: [Room]
    var labs: [LabOrder]
    var consultations: [Consultation]
    var shifts: [Shift]
    var ambulanceState: AmbulanceState
    var ambulancePending: AmbulanceRequest?
    var ambulanceLog: [AmbulanceLogEntry]
    var notices: [String]
}

enum BackendError: LocalizedError {
    case network, invalidCredentials, emailTaken, forbidden, notFound
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .network: return "Sin conexión. Revisa tu conexión e intenta de nuevo."
        case .invalidCredentials: return "Correo o contraseña incorrectos, o la cuenta todavía no está activa."
        case .emailTaken: return "Revisa los datos. Este correo ya está registrado."
        case .forbidden: return "No tienes permiso para realizar esta acción."
        case .notFound: return "No se encontró el registro solicitado."
        case .validation(let message): return message
        }
    }
}
