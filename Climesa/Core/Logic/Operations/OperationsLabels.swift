import Foundation

/// Etiquetas en español de códigos que la API entrega crudos (`medico`, `en_servicio`, ...).
/// Un código desconocido se muestra tal cual para no ocultar información nueva del servidor.
public enum StaffLabels {
    private static let functions: [String: String] = [
        "medico": "Médico", "enfermero": "Enfermería", "asistente": "Asistencia", "recepcionista": "Recepción",
        "laboratorista": "Laboratorio", "paramedico": "Paramédico", "motorista": "Motorista", "limpieza": "Limpieza",
        "administrativo": "Administración", "otro": "Otro"
    ]
    private static let shiftStates: [String: String] = [
        "borrador": "Borrador", "publicado": "Publicado", "en_curso": "En curso",
        "completado": "Completado", "cancelado": "Cancelado"
    ]
    private static let shiftTypes: [String: String] = [
        "diurno": "Diurno", "nocturno": "Nocturno", "guardia": "Guardia médica"
    ]
    private static let coverageRoles: [String: String] = [
        "medico": "Medicina", "enfermero": "Enfermería", "asistente": "Asistencia",
        "paramedico": "Paramédico", "motorista": "Motorista"
    ]
    private static let unitStates: [String: String] = [
        "disponible": "Disponible", "en_servicio": "En servicio", "en_mantenimiento": "En mantenimiento"
    ]
    private static let priorities: [String: String] = [
        "roja": "Roja", "naranja": "Naranja", "amarilla": "Amarilla", "verde": "Verde"
    ]
    private static let serviceTypes: [String: String] = [
        "emergencia_domicilio": "Emergencia a domicilio", "traslado_interhospitalario": "Traslado interhospitalario"
    ]
    private static let crewRoles: [String: String] = [
        "paramedico": "Paramédico", "motorista": "Motorista", "medico": "Médico", "enfermero": "Enfermería"
    ]

    /// Función del personal (`type` de la API): `medico` se muestra como "Médico".
    public static func function(_ code: String) -> String { functions[code] ?? code }
    public static func shiftState(_ code: String) -> String { shiftStates[code] ?? code }
    public static func shiftType(_ code: String) -> String { shiftTypes[code] ?? code }
    public static func coverageRole(_ code: String) -> String { coverageRoles[code] ?? code }
    public static func unitState(_ code: String) -> String { unitStates[code] ?? code }
    public static func priority(_ code: String) -> String { priorities[code] ?? code }
    public static func serviceType(_ code: String) -> String { serviceTypes[code] ?? code }
    public static func crewRole(_ code: String) -> String { crewRoles[code] ?? code }
}

/// Fechas de la API (ISO 8601 en UTC) mostradas en hora de El Salvador (UTC-6, sin horario de verano).
public enum OperationsDates {
    private static let zone: TimeZone = TimeZone(identifier: "America/El_Salvador") ?? TimeZone(secondsFromGMT: -6 * 3600) ?? TimeZone.current

    public static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    /// `dd/MM/yyyy HH:mm`; si no se puede interpretar devuelve "No disponible".
    public static func text(_ value: String?) -> String {
        guard let value, let date = parse(value) else { return "No disponible" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }

    /// `yyyy-MM-dd` pasa a `dd/MM/yyyy`; cualquier otro texto se devuelve igual.
    public static func dayText(_ value: String) -> String {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return value }
        return "\(parts[2])/\(parts[1])/\(parts[0])"
    }
}
