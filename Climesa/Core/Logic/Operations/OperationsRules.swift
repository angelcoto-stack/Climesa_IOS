import Foundation

/// Permisos del catálogo (`permisos.csv`) que gobiernan las pantallas de operaciones.
/// Todo se decide por permiso, nunca por el nombre de un rol (regla 8 de AGENTS.md).
public enum OperationPermission {
    public static let viewAmbulance = "ambulancia.ver_estado"
    public static let maintainAmbulance = "ambulancia.mantenimiento"
    public static let viewShifts = "turnos.ver"
    public static let planShifts = "turnos.planificar"
    public static let publishShifts = "turnos.publicar"
    public static let viewStaff = "personal.ver"
}

/// Secciones de gestión que se ofrecen dentro de Perfil / Más cuando el perfil verificado tiene el permiso.
public enum ManagementSection: String, Equatable, Hashable, Sendable, CaseIterable {
    case ambulancia, planificacion, personal

    public var title: String {
        switch self {
        case .ambulancia: return "Ambulancia"
        case .planificacion: return "Planificación de turnos"
        case .personal: return "Personal"
        }
    }

    public var symbol: String {
        switch self {
        case .ambulancia: return "cross.case"
        case .planificacion: return "calendar.badge.clock"
        case .personal: return "person.3"
        }
    }

    /// Permiso que exige la sección para entrar (solo lectura; las acciones piden el suyo).
    public var requiredPermission: String {
        switch self {
        case .ambulancia: return OperationPermission.viewAmbulance
        case .planificacion: return OperationPermission.viewShifts
        case .personal: return OperationPermission.viewStaff
        }
    }
}

extension TabPolicy {
    /// Secciones de gestión visibles: solo con acceso a iOS verificado y el permiso de lectura de cada una.
    public static func sections(for profile: AccessProfile) -> [ManagementSection] {
        guard !profile.allowedIOSRoles.isEmpty else { return [] }
        return ManagementSection.allCases.filter { profile.hasPermission($0.requiredPermission) }
    }
}

// MARK: - Motivos

public enum ReasonRules {
    public static let minLength = 10
    public static let maxLength = 500

    /// `subject` completa la frase "Indica ...": "el motivo", "el motivo de la cancelación".
    public static func error(_ reason: String, subject: String = "el motivo") -> String? {
        let size = reason.trimmingCharacters(in: .whitespacesAndNewlines).count
        if size < minLength { return "Indica \(subject), de al menos \(minLength) caracteres." }
        if size > maxLength { return "El motivo no puede pasar de \(maxLength) caracteres." }
        return nil
    }

    /// Recorta lo que se escribe al máximo permitido.
    public static func clamp(_ reason: String) -> String { String(reason.prefix(maxLength)) }
}

// MARK: - Mantenimiento de ambulancia (POST /ambulancia/mantenimiento)

public struct MaintenanceRequest: Encodable, Equatable, Sendable {
    public let version: Int
    public let inMaintenance: Bool
    public let reason: String
}

public enum MaintenanceRules {
    /// Se ofrece con el permiso del catálogo y nunca con un servicio activo.
    public static func available(profile: AccessProfile, unitState: String) -> Bool {
        profile.hasPermission(OperationPermission.maintainAmbulance) && unitState != "en_servicio"
    }

    /// Para sacar la unidad de mantenimiento debe haber un paramédico con turno en curso.
    public static func leavingBlocked(unitState: String, paramedicOnDuty: Bool) -> Bool {
        unitState == "en_mantenimiento" && !paramedicOnDuty
    }

    /// `true` si la acción saca la unidad de mantenimiento.
    public static func isLeaving(unitState: String) -> Bool { unitState == "en_mantenimiento" }

    public static let blockedMessage = "Para sacar la unidad de mantenimiento debe haber un paramédico con turno en curso."

    /// Valida y arma el cuerpo. La garantía real es la API; esto solo evita un viaje de red inútil.
    public static func prepare(status: AmbulanceStatus, profile: AccessProfile, reason: String) -> Result<MaintenanceRequest, ValidationError> {
        guard available(profile: profile, unitState: status.unit.state) else {
            return .failure(ValidationError("No puedes cambiar el mantenimiento de la unidad en este momento."))
        }
        if leavingBlocked(unitState: status.unit.state, paramedicOnDuty: status.hasParamedicOnDuty) {
            return .failure(ValidationError(blockedMessage))
        }
        if let problem = ReasonRules.error(reason) { return .failure(ValidationError(problem)) }
        return .success(MaintenanceRequest(version: status.unit.version,
                                           inMaintenance: !isLeaving(unitState: status.unit.state),
                                           reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}

// MARK: - Turnos (GET /turnos, PATCH /turnos/{id})

/// Cuerpo de `PATCH /turnos/{id}` para cancelar: la API pide el turno completo, `state`, `version` y `reason`.
public struct ShiftCancelRequest: Encodable, Equatable, Sendable {
    public let staffId: String
    public let areaId: String
    public let start: String
    public let end: String
    public let type: String
    public let state: String
    public let version: Int
    public let reason: String
}

public enum ShiftFilter: String, CaseIterable, Equatable, Sendable {
    case todos, borrador, publicado, enCurso = "en_curso", completado, cancelado

    public var title: String {
        self == .todos ? "Todos los estados" : StaffLabels.shiftState(rawValue)
    }

    public func apply(_ rows: [PlannedShift]) -> [PlannedShift] {
        self == .todos ? rows : rows.filter { $0.state == rawValue }
    }
}

public enum ShiftRules {
    public static let cancellableStates: Set<String> = ["borrador", "publicado"]

    public static func canPlan(_ profile: AccessProfile) -> Bool { profile.hasPermission(OperationPermission.planShifts) }
    public static func canPublish(_ profile: AccessProfile) -> Bool { profile.hasPermission(OperationPermission.publishShifts) }

    /// Cancelar exige `turnos.planificar`, un turno en borrador o publicado y los datos completos que pide la API.
    public static func canCancel(_ shift: PlannedShift, profile: AccessProfile) -> Bool {
        canPlan(profile) && cancellableStates.contains(shift.state) && hasCancelData(shift)
    }

    private static func hasCancelData(_ shift: PlannedShift) -> Bool {
        shift.staffId != nil && shift.areaId != nil && shift.type != nil && shift.version != nil
    }

    private static func cancelRequest(for shift: PlannedShift, reason: String) -> ShiftCancelRequest? {
        guard let staffId = shift.staffId, let areaId = shift.areaId, let type = shift.type, let version = shift.version else { return nil }
        return ShiftCancelRequest(staffId: staffId, areaId: areaId, start: shift.start, end: shift.end,
                                  type: type, state: "cancelado", version: version, reason: reason)
    }

    public static func prepareCancel(_ shift: PlannedShift, profile: AccessProfile, reason: String) -> Result<ShiftCancelRequest, ValidationError> {
        guard canCancel(shift, profile: profile) else {
            return .failure(ValidationError("Este turno no se puede cancelar."))
        }
        if let problem = ReasonRules.error(reason, subject: "el motivo de la cancelación") {
            return .failure(ValidationError(problem))
        }
        guard let request = cancelRequest(for: shift, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failure(ValidationError("Este turno no se puede cancelar."))
        }
        return .success(request)
    }
}

/// Área que se puede elegir al publicar, tomada de los turnos que la persona ya ve.
public struct AreaOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

extension ShiftRules {
    /// Áreas distintas de los turnos listados, ordenadas por nombre.
    public static func areaOptions(_ rows: [PlannedShift]) -> [AreaOption] {
        var seen = Set<String>()
        var options: [AreaOption] = []
        for row in rows {
            guard let id = row.areaId, !seen.contains(id) else { continue }
            seen.insert(id)
            options.append(AreaOption(id: id, name: row.area ?? "Área sin nombre"))
        }
        return options.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Próximos turnos de una persona: sin cancelados ni completados, que no hayan terminado, del más cercano al más lejano.
    public static func upcoming(_ rows: [PlannedShift], staffId: String, now: Date, limit: Int = 5) -> [PlannedShift] {
        let ignored: Set<String> = ["cancelado", "completado"]
        let pending = rows.filter { row in
            guard row.staffId == staffId, !ignored.contains(row.state),
                  let end = OperationsDates.parse(row.end) else { return false }
            return end >= now
        }
        let sorted = pending.sorted { left, right in
            let a = OperationsDates.parse(left.start) ?? Date.distantFuture
            let b = OperationsDates.parse(right.start) ?? Date.distantFuture
            return a < b
        }
        return Array(sorted.prefix(limit))
    }
}

// MARK: - Publicar planificación (POST /turnos/publicar)

public struct PublishRequest: Encodable, Equatable, Sendable {
    public let from: String
    public let to: String
    public let areaId: String?
}

public enum PublishRules {
    public static let maxDays = 31

    /// `yyyy-MM-dd` con el calendario indicado (el de la persona, igual que el selector de fecha).
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar
    }

    /// Fecha del día (UTC, medianoche) o `nil` si el texto no es una fecha real `yyyy-MM-dd`.
    static func day(_ text: String) -> Date? {
        guard text.count == 10 else { return nil }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else { return nil }
        let calendar = utc
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return date
    }

    public static func rangeError(from: String, to: String) -> String? {
        guard let start = day(from), let end = day(to), end >= start else {
            return "Indica el inicio y el fin del rango; el fin no puede ser anterior al inicio."
        }
        let days = utc.dateComponents([.day], from: start, to: end).day ?? 0
        if days > maxDays { return "El rango no puede pasar de \(maxDays) días." }
        return nil
    }

    public static func prepare(from: String, to: String, areaId: String?, profile: AccessProfile) -> Result<PublishRequest, ValidationError> {
        guard ShiftRules.canPublish(profile) else {
            return .failure(ValidationError("No tienes permiso para publicar turnos."))
        }
        if let problem = rangeError(from: from, to: to) { return .failure(ValidationError(problem)) }
        let area = areaId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(PublishRequest(from: from, to: to, areaId: (area?.isEmpty ?? true) ? nil : area))
    }

    /// Resumen del resultado: se publica aunque haya huecos de cobertura y se avisa cuántos.
    public static func summary(_ result: PublishResult) -> String {
        var text: String
        if result.published == 0 {
            text = "No había turnos en borrador en ese rango."
        } else {
            let noun = result.published == 1 ? "Se publicó 1 turno" : "Se publicaron \(result.published) turnos"
            if let from = result.from, let to = result.to {
                text = "\(noun) del \(OperationsDates.dayText(from)) al \(OperationsDates.dayText(to))."
            } else {
                text = "\(noun)."
            }
        }
        let gaps = result.warnings.count
        if gaps > 0 { text += gaps == 1 ? " Hay 1 hueco de cobertura." : " Hay \(gaps) huecos de cobertura." }
        return text
    }

    public static func gapText(_ gap: CoverageGap) -> String {
        let required = gap.required ?? 0
        let actual = gap.actual ?? 0
        let area = gap.area ?? "Área sin nombre"
        let role = gap.role.map { StaffLabels.coverageRole($0) } ?? "Sin función"
        return "\(area) · \(role) · \(OperationsDates.text(gap.start)) a \(OperationsDates.text(gap.end)): faltan \(max(required - actual, 0)) (mínimo \(required), programadas \(actual))"
    }
}

// MARK: - Directorio de personal (GET /personal)

public enum StaffScope: String, CaseIterable, Equatable, Sendable {
    case activos, inactivos, todos

    public var title: String {
        switch self {
        case .activos: return "Personal activo"
        case .inactivos: return "Personal inactivo"
        case .todos: return "Todo el directorio"
        }
    }
}

public enum StaffDirectory {
    /// Filtra por estado y por texto (nombres, apellidos y especialidad, sin distinguir mayúsculas ni tildes).
    public static func filter(_ rows: [StaffMember], query: String, scope: StaffScope) -> [StaffMember] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { person in
            switch scope {
            case .activos: if !person.isActive { return false }
            case .inactivos: if person.isActive { return false }
            case .todos: break
            }
            if needle.isEmpty { return true }
            let haystack = "\(person.givenNames) \(person.surnames) \(person.specialty ?? "")"
            return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    public static func vigency(_ registration: StaffRegistration) -> String {
        let from = registration.validFrom.map { OperationsDates.dayText($0) } ?? "sin inicio"
        let to = registration.validTo.map { OperationsDates.dayText($0) } ?? "sin fin"
        return "\(from) al \(to)"
    }
}
