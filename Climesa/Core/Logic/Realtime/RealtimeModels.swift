import Foundation

/// Evento delgado de dominio (docs/arquitectura/tiempo-real.md): solo dice qué cambió, nunca datos clínicos.
public struct DomainEvent: Equatable, Sendable {
    public let type: String
    public let entity: String
    public let id: String
    public let version: Int64?
    public init(type: String, entity: String, id: String, version: Int64?) {
        self.type = type; self.entity = entity; self.id = id; self.version = version
    }
}

public enum ConnectionState: String, Equatable, Sendable {
    case live, reconnecting, offline
}

/// Lo que un view model recibe del servicio de tiempo real.
public enum RealtimeSignal: Equatable, Sendable {
    case event(DomainEvent)
    case state(ConnectionState)
    /// Hay que volver a pedir los datos: se suscribieron todos los canales o se recuperó lo perdido tras una caída.
    case resync
    /// Aviso no fatal: estos canales fueron rechazados varias veces seguidas y se dejaron fuera; el resto sigue en vivo.
    case channelsDropped(Set<String>)
}

/// Respuesta de `GET /eventos?after=<seq>`.
public struct CatchUp: Equatable, Sendable {
    public let cursor: String
    public let events: [DomainEvent]
    public init(cursor: String, events: [DomainEvent]) { self.cursor = cursor; self.events = events }
}

public enum RealtimeFrame: Equatable, Sendable {
    case joinReply(channel: String, ok: Bool)
    case broadcast(channel: String, event: DomainEvent)
    case channelClosed(channel: String)
    /// Respuesta (`phx_reply`) al latido del protocolo, en el tema `phoenix`.
    case heartbeatReply(ref: String)
    case ignored
}

/// Eventos del socket, ya independientes del transporte (URLSession o un doble de prueba).
public enum SocketEvent: Equatable, Sendable {
    case opened
    case text(String)
    case closed(String?)
}

/// Un socket abierto. `events` termina cuando el socket se cierra.
public protocol RealtimeSocket: Sendable {
    var events: AsyncStream<SocketEvent> { get }
    func send(_ text: String) async -> Bool
    func close()
}

public protocol RealtimeSocketFactory: Sendable {
    func open(url: String) -> RealtimeSocket
}

/// Tiempo real sin sondeo (regla 9): los cambios llegan empujados; nunca se consulta por reloj.
public protocol RealtimeService: Sendable {
    /// Abre la conexión mientras se consume el flujo y la cierra al cancelar la tarea que lo consume.
    func observe(channels: [String]) -> AsyncStream<RealtimeSignal>
}
