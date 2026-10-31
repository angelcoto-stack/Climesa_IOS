import Foundation

// MARK: - Utilidades

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Textos de la interfaz que viven en Localizable.xcstrings (español como idioma base).
enum L {
    static func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }
}

// MARK: - Áreas y perfil

/// Áreas de la app con diseño propio (shell con barra inferior): Medicina y Paciente.
/// El rawValue coincide con el código de rol que entrega /auth/me ("MED" y "PAC").
enum Area: String, CaseIterable, Identifiable {
    case med = "MED", pac = "PAC"
    var id: String { rawValue }
    var code: String { rawValue }
    var title: String { self == .med ? "Medicina" : "Paciente" }
}

/// Lo único que la app conoce de la sesión: el perfil verificado por la API (/auth/me).
struct UserProfile: Identifiable {
    let access: AccessProfile

    var id: String { access.id }
    var name: String { access.name }
    var email: String { access.email }
    var roles: [String] { access.roles }
    var channels: [String] { access.channels }

    /// Roles con acceso a iOS (Médico y/o Paciente) según plataformas y permisos verificados.
    var areas: [Area] { access.allowedIOSRoles.compactMap { Area(rawValue: $0) } }

    /// Si es falso, se muestra "Tu rol no usa esta aplicación".
    var isSupported: Bool { !areas.isEmpty }

    var firstName: String {
        let parts = name.split(separator: " ").map(String.init)
        if let first = parts.first, first.hasSuffix("."), parts.count > 1 { return parts[1] }
        return parts.first ?? name
    }
}

// MARK: - Turnos (GET /turnos/mios)

/// Fila tal como la entrega la API. Las fechas llegan en ISO 8601.
struct TurnoAPI: Decodable, Identifiable {
    let id: String
    let area: String
    let start: String
    let end: String
    let state: String
}

/// Turno listo para mostrar en "Mis turnos".
struct ShiftOccurrence: Identifiable {
    let id: String
    let service: String
    let start: Date?
    let end: Date?
    let published: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.timeZone = TimeZone(identifier: "America/El_Salvador")
        f.dateFormat = "d 'de' MMMM 'de' yyyy, h:mm a"
        return f
    }()

    private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    /// /turnos/mios solo devuelve turnos publicados.
    init(_ row: TurnoAPI) {
        id = row.id
        service = row.area
        start = Self.parse(row.start)
        end = Self.parse(row.end)
        published = true
    }

    var startText: String { start.map { Self.formatter.string(from: $0) } ?? L.text("shift.unavailable") }
    var endText: String {
        "Hasta " + (end.map { Self.formatter.string(from: $0) } ?? L.text("shift.unavailable"))
    }
}
