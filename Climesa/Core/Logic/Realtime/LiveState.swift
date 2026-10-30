import Foundation

/// Qué eventos obligan a volver a pedir cada grupo de datos.
public enum InvalidationRule {
    public static func affectsShifts(_ event: DomainEvent) -> Bool {
        event.type.hasPrefix("turno.") || event.entity == "turno"
    }

    /// Una cuenta de usuario cambió: conviene verificar de nuevo el perfil (roles y permisos).
    public static func affectsProfile(_ event: DomainEvent) -> Bool {
        event.entity == "usuario"
    }
}

/// Estado de tiempo real que ven las pantallas. Cada contador sube cuando hay que volver a pedir esos datos.
public struct LiveSnapshot: Equatable, Sendable {
    public var connection: ConnectionState
    public var version: Int
    public var shiftsVersion: Int
    public var profileVersion: Int
    public init(connection: ConnectionState = .reconnecting, version: Int = 0, shiftsVersion: Int = 0, profileVersion: Int = 0) {
        self.connection = connection; self.version = version; self.shiftsVersion = shiftsVersion; self.profileVersion = profileVersion
    }
}

public enum LiveReducer {
    public static func apply(_ signal: RealtimeSignal, to snapshot: LiveSnapshot) -> LiveSnapshot {
        var next = snapshot
        switch signal {
        case .state(let state):
            next.connection = state
        case .resync:
            next.version += 1
            next.shiftsVersion += 1
        case .event(let event):
            next.version += 1
            if InvalidationRule.affectsShifts(event) { next.shiftsVersion += 1 }
            if InvalidationRule.affectsProfile(event) { next.profileVersion += 1 }
        }
        return next
    }
}
