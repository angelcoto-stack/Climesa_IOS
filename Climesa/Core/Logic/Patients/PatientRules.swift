import Foundation

// MARK: - Permisos del catálogo (permisos.csv) de pacientes

public enum PatientPermission {
    public static let search = "pacientes.buscar"
    public static let register = "pacientes.registrar"
    public static let viewFile = "pacientes.ver_ficha"
    /// Corregir datos e inactivar comparten permiso en el catálogo (`POST /pacientes/{id}/estado`).
    public static let edit = "pacientes.editar_demograficos"
}

// MARK: - Modelos (GET /pacientes, POST /pacientes/busquedas, GET /pacientes/{id})

public enum PatientSex: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case femenino, masculino, indeterminado
    case noRegistrado = "no_registrado"

    public var title: String {
        switch self {
        case .femenino: return "Femenino"
        case .masculino: return "Masculino"
        case .indeterminado: return "Indeterminado"
        case .noRegistrado: return "No registrado"
        }
    }
}

/// Paciente tal como lo entrega la API. Los campos que puede omitir son opcionales.
public struct PatientRecord: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let record: String?
    public let givenNames: String
    public let surnames: String
    public let dui: String?
    public let birth: String?
    public let sex: String?
    public let phone: String?
    public let active: Bool?
    public let version: Int

    public var isActive: Bool { active ?? true }
    public var fullName: String { "\(givenNames) \(surnames)".trimmingCharacters(in: .whitespacesAndNewlines) }
}

public struct PatientHistoryChange: Decodable, Equatable, Sendable {
    public let before: String?
    public let after: String?
}

public struct PatientHistoryEntry: Decodable, Equatable, Identifiable, Sendable {
    public let version: Int
    public let reason: String
    public let at: String
    public let changes: [String: PatientHistoryChange]?

    public var id: Int { version }
}

/// Ficha: los datos del paciente más su historial de cambios (`history`), en la misma respuesta.
public struct PatientFile: Decodable, Equatable, Sendable {
    public let patient: PatientRecord
    public let history: [PatientHistoryEntry]

    private enum CodingKeys: String, CodingKey { case history }

    public init(from decoder: Decoder) throws {
        patient = try PatientRecord(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        history = try container.decodeIfPresent([PatientHistoryEntry].self, forKey: .history) ?? []
    }
}

/// Cuerpo de `POST /pacientes/busquedas`.
public struct PatientSearchRequest: Encodable, Equatable, Sendable {
    public let query: String
    public init(query: String) { self.query = query }
}

/// Respuesta de la búsqueda previa: candidatos, token y vencimiento. El alta exige este token.
public struct PatientSearchResult: Decodable, Equatable, Sendable {
    public let candidates: [PatientRecord]
    public let token: String
    public let expiresAt: String
}

/// Cuerpo de `POST /pacientes`. Los campos opcionales no enviados se omiten.
public struct PatientCreateRequest: Encodable, Equatable, Sendable {
    public let givenNames: String
    public let surnames: String
    public let sex: String
    public let dui: String?
    public let birth: String?
    public let phone: String?
    public let searchToken: String
    public let searchQuery: String
}

/// Cuerpo de `PATCH /pacientes/{id}`: versión que se vio y motivo del cambio.
public struct PatientUpdateRequest: Encodable, Equatable, Sendable {
    public let givenNames: String
    public let surnames: String
    public let sex: String
    public let dui: String?
    public let birth: String?
    public let phone: String?
    public let version: Int
    public let reason: String
}

/// Cuerpo de `POST /pacientes/{id}/estado`: nunca borra, solo activa o inactiva.
public struct PatientStateRequest: Encodable, Equatable, Sendable {
    public let active: Bool
    public let version: Int
    public let reason: String
}

/// Datos del formulario de un paciente, en texto como los escribe la persona.
public struct PatientDraft: Equatable, Sendable {
    public var givenNames: String
    public var surnames: String
    public var sex: PatientSex?
    public var dui: String
    public var birth: String
    public var phone: String

    public init(givenNames: String = "", surnames: String = "", sex: PatientSex? = nil,
                dui: String = "", birth: String = "", phone: String = "") {
        self.givenNames = givenNames
        self.surnames = surnames
        self.sex = sex
        self.dui = dui
        self.birth = birth
        self.phone = phone
    }

    public init(record: PatientRecord) {
        self.givenNames = record.givenNames
        self.surnames = record.surnames
        self.sex = record.sex.flatMap { PatientSex(rawValue: $0) }
        self.dui = record.dui ?? ""
        self.birth = record.birth.map { String($0.prefix(10)) } ?? ""
        self.phone = record.phone ?? ""
    }
}

// MARK: - Reglas

public enum PatientRules {
    public static let searchMinLength = 3
    public static let searchMaxLength = 100
    public static let nameLengths = 2...120

    public static func canSearch(_ profile: AccessProfile) -> Bool { profile.hasPermission(PatientPermission.search) }
    public static func canRegister(_ profile: AccessProfile) -> Bool { profile.hasPermission(PatientPermission.register) }
    public static func canEdit(_ profile: AccessProfile) -> Bool { profile.hasPermission(PatientPermission.edit) }
    public static func canViewFile(_ profile: AccessProfile) -> Bool { profile.hasPermission(PatientPermission.viewFile) }

    /// La búsqueda necesita al menos 3 caracteres (criterio de la app; la API valida el resto).
    public static func searchError(_ query: String) -> String? {
        let size = query.trimmingCharacters(in: .whitespacesAndNewlines).count
        if size < searchMinLength { return "Escribe al menos \(searchMinLength) caracteres para buscar." }
        if size > searchMaxLength { return "La búsqueda no puede pasar de \(searchMaxLength) caracteres." }
        return nil
    }

    /// Errores de los datos personales. Lista vacía = formulario válido. DUI, fecha de nacimiento y teléfono son opcionales.
    public static func draftErrors(_ draft: PatientDraft) -> [String] {
        var errors: [String] = []
        let given = draft.givenNames.trimmingCharacters(in: .whitespacesAndNewlines).count
        let surnames = draft.surnames.trimmingCharacters(in: .whitespacesAndNewlines).count
        if !nameLengths.contains(given) { errors.append("Escribe los nombres de la persona (de 2 a 120 caracteres).") }
        if !nameLengths.contains(surnames) { errors.append("Escribe los apellidos de la persona (de 2 a 120 caracteres).") }
        if draft.sex == nil { errors.append("Indica el sexo registrado.") }
        let dui = draft.dui.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dui.isEmpty && dui.range(of: #"^\d{8}-\d$"#, options: .regularExpression) == nil {
            errors.append("El DUI debe tener el formato 00000000-0.")
        }
        let birth = draft.birth.trimmingCharacters(in: .whitespacesAndNewlines)
        if !birth.isEmpty && !isRealDay(birth) {
            errors.append("La fecha de nacimiento debe ser una fecha real con formato AAAA-MM-DD.")
        }
        let phone = draft.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty && !(phone.allSatisfy { $0.isNumber || $0 == " " || $0 == "-" } && phone.filter { $0.isNumber }.count == 8) {
            errors.append("El teléfono debe tener 8 dígitos.")
        }
        return errors
    }

    /// Alta: exige permiso, formulario válido y una búsqueda previa vigente (el token viene de `POST /pacientes/busquedas`).
    public static func prepareCreate(_ draft: PatientDraft, searchQuery: String, search: PatientSearchResult?,
                                     profile: AccessProfile, now: Date) -> Result<PatientCreateRequest, ValidationError> {
        guard canRegister(profile) else {
            return .failure(ValidationError("No tienes permiso para registrar pacientes."))
        }
        if let problem = draftErrors(draft).first { return .failure(ValidationError(problem)) }
        guard let sex = draft.sex else { return .failure(ValidationError("Indica el sexo registrado.")) }
        guard let search, !search.token.isEmpty,
              let expires = OperationsDates.parse(search.expiresAt), expires > now else {
            return .failure(ValidationError("Busca al paciente antes de registrarlo; la búsqueda venció."))
        }
        return .success(PatientCreateRequest(givenNames: draft.givenNames.trimmingCharacters(in: .whitespacesAndNewlines),
                                             surnames: draft.surnames.trimmingCharacters(in: .whitespacesAndNewlines),
                                             sex: sex.rawValue,
                                             dui: optionalText(draft.dui),
                                             birth: optionalText(draft.birth),
                                             phone: optionalText(draft.phone),
                                             searchToken: search.token,
                                             searchQuery: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// Corrección de datos: versión que se vio al abrir la ficha y motivo de 10 a 500 caracteres.
    public static func prepareUpdate(_ draft: PatientDraft, current: PatientRecord, reason: String,
                                     profile: AccessProfile) -> Result<PatientUpdateRequest, ValidationError> {
        guard canEdit(profile) else {
            return .failure(ValidationError("No tienes permiso para editar pacientes."))
        }
        if let problem = draftErrors(draft).first { return .failure(ValidationError(problem)) }
        guard let sex = draft.sex else { return .failure(ValidationError("Indica el sexo registrado.")) }
        if let problem = ReasonRules.error(reason) { return .failure(ValidationError(problem)) }
        return .success(PatientUpdateRequest(givenNames: draft.givenNames.trimmingCharacters(in: .whitespacesAndNewlines),
                                             surnames: draft.surnames.trimmingCharacters(in: .whitespacesAndNewlines),
                                             sex: sex.rawValue,
                                             dui: optionalText(draft.dui),
                                             birth: optionalText(draft.birth),
                                             phone: optionalText(draft.phone),
                                             version: current.version,
                                             reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// Inactivar o reactivar. No borra: el motivo queda en el historial.
    public static func prepareStateChange(_ patient: PatientRecord, active: Bool, reason: String,
                                          profile: AccessProfile) -> Result<PatientStateRequest, ValidationError> {
        guard canEdit(profile) else {
            return .failure(ValidationError("No tienes permiso para cambiar el estado de pacientes."))
        }
        if patient.isActive == active {
            return .failure(ValidationError(active ? "El paciente ya está activo." : "El paciente ya está inactivo."))
        }
        let subject = active ? "el motivo de la reactivación" : "el motivo de la inactivación"
        if let problem = ReasonRules.error(reason, subject: subject) { return .failure(ValidationError(problem)) }
        return .success(PatientStateRequest(active: active, version: patient.version,
                                            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    // MARK: Ayudas

    private static func optionalText(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// `AAAA-MM-DD` que existe en el calendario (no acepta 30 de febrero).
    static func isRealDay(_ text: String) -> Bool {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = calendar.date(from: components) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == parts[0] && back.month == parts[1] && back.day == parts[2]
    }
}
