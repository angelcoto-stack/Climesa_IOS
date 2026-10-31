import Foundation

// MARK: - Personal: crear, editar e inactivar (POST /personal, PATCH /personal/{id})

/// Permisos del catálogo (`permisos.csv`) del personal de salud.
public enum StaffPermission {
    public static let manage = "personal.gestionar"
    /// DUI y teléfono del personal: solo quien tiene este permiso ve y escribe esos campos.
    public static let personalData = "personal.ver_datos_personales"
}

/// Datos del formulario de personal, en texto como los escribe la persona.
public struct StaffDraft: Equatable, Sendable {
    public var givenNames: String
    public var surnames: String
    public var type: String
    public var specialty: String
    public var dui: String
    public var phone: String

    public init(givenNames: String = "", surnames: String = "", type: String = "",
                specialty: String = "", dui: String = "", phone: String = "") {
        self.givenNames = givenNames
        self.surnames = surnames
        self.type = type
        self.specialty = specialty
        self.dui = dui
        self.phone = phone
    }

    /// El directorio no entrega DUI ni teléfono, así que el formulario de edición los deja en blanco (no se envían).
    public init(member: StaffMember) {
        self.givenNames = member.givenNames
        self.surnames = member.surnames
        self.type = member.type
        self.specialty = member.specialty ?? ""
        self.dui = ""
        self.phone = ""
    }
}

/// Cuerpo de `POST /personal`. Los campos opcionales no enviados se omiten.
public struct StaffCreateRequest: Encodable, Equatable, Sendable {
    public let givenNames: String
    public let surnames: String
    public let type: String
    public let specialty: String?
    public let dui: String?
    public let phone: String?
}

/// Cuerpo de `PATCH /personal/{id}`: versión que se vio y motivo. Inactivar usa el mismo cuerpo con `active` en falso.
public struct StaffUpdateRequest: Encodable, Equatable, Sendable {
    public let givenNames: String
    public let surnames: String
    public let type: String
    public let specialty: String?
    public let dui: String?
    public let phone: String?
    public let active: Bool
    public let version: Int
    public let reason: String
}

public enum StaffWriteRules {
    public static let nameLengths = 2...120
    public static let specialtyMaxLength = 120

    public static func canManage(_ profile: AccessProfile) -> Bool { profile.hasPermission(StaffPermission.manage) }
    public static func canSeePersonalData(_ profile: AccessProfile) -> Bool { profile.hasPermission(StaffPermission.personalData) }

    /// Errores del formulario. Lista vacía = válido. La función debe ser un código de `StaffLabels`.
    public static func draftErrors(_ draft: StaffDraft) -> [String] {
        var errors: [String] = []
        if !nameLengths.contains(draft.givenNames.trimmingCharacters(in: .whitespacesAndNewlines).count) {
            errors.append("Escribe los nombres de la persona (de 2 a 120 caracteres).")
        }
        if !nameLengths.contains(draft.surnames.trimmingCharacters(in: .whitespacesAndNewlines).count) {
            errors.append("Escribe los apellidos de la persona (de 2 a 120 caracteres).")
        }
        if !StaffLabels.functionCodes.contains(draft.type) {
            errors.append("Elige la función del personal.")
        }
        if draft.specialty.trimmingCharacters(in: .whitespacesAndNewlines).count > specialtyMaxLength {
            errors.append("La especialidad no puede pasar de \(specialtyMaxLength) caracteres.")
        }
        let dui = draft.dui.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dui.isEmpty && dui.range(of: #"^\d{8}-\d$"#, options: .regularExpression) == nil {
            errors.append("El DUI debe tener el formato 00000000-0.")
        }
        let phone = draft.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty && !(phone.allSatisfy { $0.isNumber || $0 == " " || $0 == "-" } && phone.filter { $0.isNumber }.count == 8) {
            errors.append("El teléfono debe tener 8 dígitos.")
        }
        return errors
    }

    public static func prepareCreate(_ draft: StaffDraft, profile: AccessProfile) -> Result<StaffCreateRequest, ValidationError> {
        guard canManage(profile) else {
            return .failure(ValidationError("No tienes permiso para registrar personal."))
        }
        if let problem = draftErrors(draft).first { return .failure(ValidationError(problem)) }
        let personal = canSeePersonalData(profile)
        return .success(StaffCreateRequest(givenNames: draft.givenNames.trimmingCharacters(in: .whitespacesAndNewlines),
                                           surnames: draft.surnames.trimmingCharacters(in: .whitespacesAndNewlines),
                                           type: draft.type,
                                           specialty: optionalText(draft.specialty),
                                           dui: personal ? optionalText(draft.dui) : nil,
                                           phone: personal ? optionalText(draft.phone) : nil))
    }

    public static func prepareUpdate(_ draft: StaffDraft, current: StaffMember, reason: String,
                                     profile: AccessProfile) -> Result<StaffUpdateRequest, ValidationError> {
        guard canManage(profile) else {
            return .failure(ValidationError("No tienes permiso para editar personal."))
        }
        if let problem = draftErrors(draft).first { return .failure(ValidationError(problem)) }
        if let problem = ReasonRules.error(reason) { return .failure(ValidationError(problem)) }
        guard let version = current.version else {
            return .failure(ValidationError("No se puede editar: falta la versión del registro. Vuelve a abrirlo."))
        }
        let personal = canSeePersonalData(profile)
        return .success(StaffUpdateRequest(givenNames: draft.givenNames.trimmingCharacters(in: .whitespacesAndNewlines),
                                           surnames: draft.surnames.trimmingCharacters(in: .whitespacesAndNewlines),
                                           type: draft.type,
                                           specialty: optionalText(draft.specialty),
                                           dui: personal ? optionalText(draft.dui) : nil,
                                           phone: personal ? optionalText(draft.phone) : nil,
                                           active: current.isActive,
                                           version: version,
                                           reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// Inactivar o reactivar a una persona del personal. Conserva el registro; el motivo es obligatorio.
    public static func prepareActiveChange(_ member: StaffMember, active: Bool, reason: String,
                                           profile: AccessProfile) -> Result<StaffUpdateRequest, ValidationError> {
        guard canManage(profile) else {
            return .failure(ValidationError("No tienes permiso para cambiar el estado del personal."))
        }
        if member.isActive == active {
            return .failure(ValidationError(active ? "Esta persona ya está activa." : "Esta persona ya está inactiva."))
        }
        let subject = active ? "el motivo de la reactivación" : "el motivo de la inactivación"
        if let problem = ReasonRules.error(reason, subject: subject) { return .failure(ValidationError(problem)) }
        guard let version = member.version else {
            return .failure(ValidationError("No se puede cambiar el estado: falta la versión del registro. Vuelve a abrirlo."))
        }
        return .success(StaffUpdateRequest(givenNames: member.givenNames, surnames: member.surnames, type: member.type,
                                           specialty: member.specialty, dui: nil, phone: nil, active: active,
                                           version: version, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private static func optionalText(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
