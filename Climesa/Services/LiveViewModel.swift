import Foundation

/// Consume el flujo de tiempo real y expone el estado de conexión y los contadores de invalidación.
/// Las vistas usan esos contadores como `id` de `.task(id:)` para volver a pedir sus datos (sin temporizadores).
@MainActor
final class LiveViewModel: ObservableObject {
    @Published private(set) var snapshot = LiveSnapshot()

    /// Se llama desde `.task {}`: termina cuando SwiftUI cancela la tarea, y eso cierra la conexión.
    func run(service: (any RealtimeService)?, channels: [String]) async {
        let needed = RealtimeProtocol.subscribableChannels(channels)
        guard let service, !needed.isEmpty else {
            snapshot.connection = .offline
            return
        }
        snapshot = LiveSnapshot()
        for await signal in service.observe(channels: needed) {
            snapshot = LiveReducer.apply(signal, to: snapshot)
        }
    }
}
