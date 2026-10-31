import Foundation

/// Cuerpo de error `application/problem+json` de la API (`detail`, `codigo`, `versionActual`),
/// con respaldo al formato anterior `error.message`.
public struct APIProblem: Decodable, Equatable, Sendable {
    public struct Nested: Decodable, Equatable, Sendable {
        public let message: String?
    }
    public let detail: String?
    public let codigo: String?
    public let versionActual: Int?
    public let error: Nested?

    public var text: String? {
        if let detail, !detail.isEmpty { return detail }
        if let message = error?.message, !message.isEmpty { return message }
        return nil
    }
}

/// Resultado de una escritura rechazada por la API.
public enum WriteFailure: Equatable, Sendable {
    /// 409 por versión desactualizada: otra persona cambió el registro y nada se guardó.
    case versionConflict(String)
    case rejected(String)

    public var text: String {
        switch self {
        case .versionConflict(let text), .rejected(let text): return text
        }
    }

    public var isVersionConflict: Bool {
        if case .versionConflict = self { return true }
        return false
    }
}

public enum ProblemMapper {
    public static let defaultMessage = "No se pudo completar la operación. Vuelve a intentar."
    public static let defaultConflictMessage = "El registro cambió. Vuelve a abrirlo para ver su estado actual; el cambio no se guardó."

    /// Un 409 es conflicto de versión cuando trae `codigo: version_conflicto` o la `versionActual`
    /// (mismo criterio que la web); otros 409 se muestran con el texto de la API.
    public static func failure(status: Int, body: Data, fallback: String = defaultMessage) -> WriteFailure {
        let problem = try? JSONDecoder().decode(APIProblem.self, from: body)
        let text = problem?.text
        if status == 409, problem?.codigo == "version_conflicto" || problem?.versionActual != nil {
            return .versionConflict(text ?? defaultConflictMessage)
        }
        return .rejected(text ?? fallback)
    }
}

/// Motivo, en español, por el que todavía no se puede enviar la solicitud.
public struct ValidationError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// `Idempotency-Key` de las escrituras: un reintento de la misma solicitud reutiliza la clave
/// (así la API no duplica la operación) y cada solicitud nueva usa una clave nueva.
public struct IdempotencyKeys {
    private var attempts: [String: String] = [:]
    private let generate: () -> String

    public init(generate: @escaping () -> String = { UUID().uuidString }) {
        self.generate = generate
    }

    public static func signature(method: String, path: String, body: Data?) -> String {
        let text = body.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return "\(method) \(path) \(text)"
    }

    public mutating func key(for signature: String) -> String {
        if let existing = attempts[signature] { return existing }
        let created = generate()
        attempts[signature] = created
        return created
    }

    /// La solicitud terminó bien: la próxima igual es una operación nueva.
    public mutating func complete(_ signature: String) {
        attempts[signature] = nil
    }

    public var pendingCount: Int { attempts.count }
}
