import Foundation

// Modelos de las respuestas de la API de operaciones (ambulancia, turnos y personal).
// Los campos que la API puede omitir son opcionales para que una fila incompleta no tumbe toda la pantalla.

// MARK: - Ambulancia (GET /ambulancia)

public struct AmbulanceUnit: Decodable, Equatable, Sendable {
    public let id: String
    public let plate: String
    public let state: String
    public let version: Int
    public init(id: String, plate: String, state: String, version: Int) {
        self.id = id; self.plate = plate; self.state = state; self.version = version
    }
}

public struct CrewMember: Decodable, Equatable, Sendable {
    public let staffId: String?
    public let role: String?
    public let name: String?
    public init(staffId: String?, role: String?, name: String?) {
        self.staffId = staffId; self.role = role; self.name = name
    }
}

/// Servicio activo; la API no entrega datos del paciente.
public struct AmbulanceService: Decodable, Equatable, Sendable {
    public let id: String?
    public let type: String?
    public let priority: String?
    public let origin: String?
    public let destination: String?
    public let dispatchedAt: String?
    public let crew: [CrewMember]?
    public init(id: String?, type: String?, priority: String?, origin: String?, destination: String?,
                dispatchedAt: String?, crew: [CrewMember]?) {
        self.id = id; self.type = type; self.priority = priority; self.origin = origin
        self.destination = destination; self.dispatchedAt = dispatchedAt; self.crew = crew
    }
}

public struct AmbulanceStatus: Decodable, Equatable, Sendable {
    public let unit: AmbulanceUnit
    public let activeService: AmbulanceService?
    public let paramedicOnDuty: Bool?
    public init(unit: AmbulanceUnit, activeService: AmbulanceService?, paramedicOnDuty: Bool?) {
        self.unit = unit; self.activeService = activeService; self.paramedicOnDuty = paramedicOnDuty
    }
    /// Si la API no lo informa se asume que no hay paramédico, que es lo más prudente para sacar la unidad de mantenimiento.
    public var hasParamedicOnDuty: Bool { paramedicOnDuty ?? false }
}

// MARK: - Turnos (GET /turnos)

public struct PlannedShift: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let staffId: String?
    public let person: String?
    public let areaId: String?
    public let area: String?
    public let start: String
    public let end: String
    public let type: String?
    public let state: String
    public let justification: String?
    public let version: Int?
    public init(id: String, staffId: String?, person: String?, areaId: String?, area: String?, start: String,
                end: String, type: String?, state: String, justification: String? = nil, version: Int?) {
        self.id = id; self.staffId = staffId; self.person = person; self.areaId = areaId; self.area = area
        self.start = start; self.end = end; self.type = type; self.state = state
        self.justification = justification; self.version = version
    }
}

/// Hueco de cobertura que `POST /turnos/publicar` devuelve como advertencia (se publica igual).
public struct CoverageGap: Decodable, Equatable, Sendable {
    public let areaId: String?
    public let area: String?
    public let role: String?
    public let start: String?
    public let end: String?
    public let required: Int?
    public let actual: Int?
    public init(areaId: String?, area: String?, role: String?, start: String?, end: String?, required: Int?, actual: Int?) {
        self.areaId = areaId; self.area = area; self.role = role; self.start = start; self.end = end
        self.required = required; self.actual = actual
    }
}

public struct PublishResult: Decodable, Equatable, Sendable {
    public let from: String?
    public let to: String?
    public let published: Int
    public let warnings: [CoverageGap]
    public init(from: String?, to: String?, published: Int, warnings: [CoverageGap]) {
        self.from = from; self.to = to; self.published = published; self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey { case from, to, published, warnings }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.from = try container.decodeIfPresent(String.self, forKey: .from)
        self.to = try container.decodeIfPresent(String.self, forKey: .to)
        self.published = try container.decodeIfPresent(Int.self, forKey: .published) ?? 0
        self.warnings = try container.decodeIfPresent([CoverageGap].self, forKey: .warnings) ?? []
    }
}

// MARK: - Personal (GET /personal)

public struct StaffRegistration: Decodable, Equatable, Sendable {
    public let id: String?
    public let board: String?
    public let number: String?
    public let validFrom: String?
    public let validTo: String?
    public init(id: String?, board: String?, number: String?, validFrom: String?, validTo: String?) {
        self.id = id; self.board = board; self.number = number; self.validFrom = validFrom; self.validTo = validTo
    }
    /// Para listar sin depender de que la API envíe `id`.
    public var rowKey: String { id ?? "\(board ?? "")-\(number ?? "")-\(validFrom ?? "")" }
}

public struct StaffMember: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let givenNames: String
    public let surnames: String
    public let type: String
    public let specialty: String?
    public let area: String?
    public let active: Bool?
    public let version: Int?
    public let registrations: [StaffRegistration]?
    public init(id: String, givenNames: String, surnames: String, type: String, specialty: String? = nil,
                area: String? = nil, active: Bool? = true, version: Int? = nil, registrations: [StaffRegistration]? = nil) {
        self.id = id; self.givenNames = givenNames; self.surnames = surnames; self.type = type
        self.specialty = specialty; self.area = area; self.active = active; self.version = version
        self.registrations = registrations
    }

    // No se decodifican DUI ni teléfono: la app no los muestra.
    private enum CodingKeys: String, CodingKey {
        case id, givenNames, surnames, type, specialty, area, active, version, registrations
    }

    public var fullName: String { "\(givenNames) \(surnames)".trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isActive: Bool { active ?? true }
}
