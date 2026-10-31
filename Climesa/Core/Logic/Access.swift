import Foundation
public struct Permission: Codable, Equatable, Sendable {
    public let code: String
    public let context: String
    public init(code: String, context: String) { self.code = code; self.context = context }
}
public struct AccessProfile: Codable, Sendable {
    public let id: String
    public let email: String
    public let name: String
    public let roles: [String]
    public let platforms: [String]
    public let permissions: [Permission]
    /// Canales de Realtime a los que el usuario puede unirse (los entrega /auth/me). Vacío si la API no los envía.
    public let channels: [String]
    public init(id: String, email: String, name: String, roles: [String], platforms: [String], permissions: [Permission], channels: [String] = []) {
        self.id=id; self.email=email; self.name=name; self.roles=roles; self.platforms=platforms; self.permissions=permissions; self.channels=channels
    }
    private enum CodingKeys: String, CodingKey { case id, email, name, roles, platforms, permissions, channels }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        name = try container.decode(String.self, forKey: .name)
        roles = try container.decode([String].self, forKey: .roles)
        platforms = try container.decode([String].self, forKey: .platforms)
        permissions = try container.decode([Permission].self, forKey: .permissions)
        channels = try container.decodeIfPresent([String].self, forKey: .channels) ?? []
    }
    public func hasPermission(_ code: String) -> Bool { permissions.contains { $0.code == code } }
    // Solo se invoca con el perfil verificado que devuelve /auth/me; nunca con metadatos del JWT.
    public var allowedIOSRoles: [String] {
        guard platforms.contains("ios"), permissions.contains(where: { $0.code == "sesion.perfil" }) else { return [] }
        return ["MED", "PAC"].filter { roles.contains($0) }
    }
}
public enum RolePolicy {
    /// Clave de Localizable.xcstrings con el nombre visible del rol.
    public static func labelKey(_ role: String) -> String { role == "MED" ? "role.MED" : "role.PAC" }
}

/// Pestañas de la app (spec 122, escenario 1). Médico: Mi día, Pacientes, Resultados, Turnos, Perfil.
/// Paciente: Inicio, Fila, Citas, Exámenes, Más.
public enum AppTab: String, Equatable, Hashable, Sendable, CaseIterable {
    case miDia, pacientes, resultados, turnos, perfil
    case inicio, fila, citas, examenes, mas

    /// Clave de Localizable.xcstrings con el título de la pestaña.
    public var titleKey: String { "tab.\(rawValue)" }

    public var symbol: String {
        switch self {
        case .miDia: return "calendar.day.timeline.left"
        case .pacientes: return "person.2"
        case .resultados: return "doc.text"
        case .turnos: return "clock"
        case .perfil: return "person.crop.circle"
        case .inicio: return "house"
        case .fila: return "list.number"
        case .citas: return "calendar"
        case .examenes: return "testtube.2"
        case .mas: return "ellipsis.circle"
        }
    }

    /// Las demás pestañas muestran el aviso "Próxima entrega".
    public var isImplemented: Bool { self == .turnos || self == .perfil || self == .mas }

    /// Permiso que la pestaña exige además del rol (regla 8 de AGENTS.md: se pregunta por permiso).
    public var requiredPermission: String? {
        switch self {
        case .pacientes: return "pacientes.buscar"
        case .turnos: return "turnos.ver"
        case .fila: return "fila.ver"
        case .citas: return "citas.ver"
        case .resultados, .examenes: return "resultados.ver"
        default: return nil
        }
    }
}

public enum AccessDecision: Equatable, Sendable {
    case tabs(role: String, tabs: [AppTab])
    /// Ni Médico ni Paciente con acceso a iOS: se muestra "Tu rol no usa esta aplicación".
    case unsupportedRole
}

public enum TabPolicy {
    public static func candidates(for role: String) -> [AppTab] {
        role == "MED" ? [.miDia, .pacientes, .resultados, .turnos, .perfil] : [.inicio, .fila, .citas, .examenes, .mas]
    }

    /// Decide con el perfil verificado de /auth/me. `preferredRole` solo aplica si la cuenta tiene ese rol en iOS.
    public static func decide(_ profile: AccessProfile, preferredRole: String? = nil) -> AccessDecision {
        let allowed = profile.allowedIOSRoles
        guard let first = allowed.first else { return .unsupportedRole }
        let role = preferredRole.flatMap { allowed.contains($0) ? $0 : nil } ?? first
        let tabs = candidates(for: role).filter { tab in
            guard let code = tab.requiredPermission else { return true }
            return profile.hasPermission(code)
        }
        return .tabs(role: role, tabs: tabs)
    }
}
public enum RegistrationRules {
    public static func errors(name: String, email: String, password: String, confirmation: String) -> [String] {
        var errors: [String] = []
        let size = name.trimmingCharacters(in: .whitespacesAndNewlines).count
        if !(2...120).contains(size) { errors.append("Escribe tu nombre completo.") }
        if email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil { errors.append("Ingresa un correo válido.") }
        if password.count < 8 || password.rangeOfCharacter(from: .uppercaseLetters) == nil || password.rangeOfCharacter(from: .lowercaseLetters) == nil || password.rangeOfCharacter(from: .decimalDigits) == nil || password.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) { errors.append("Usa 8 caracteres, mayúscula, minúscula, número y símbolo.") }
        if password != confirmation { errors.append("Las contraseñas no coinciden.") }
        return errors
    }
}
