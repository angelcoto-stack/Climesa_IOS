import SwiftUI

/// Carga de un recurso de la API (GET). Se vuelve a pedir solo al entrar y cuando llega un evento en vivo (sin sondeo).
@MainActor
final class RemoteResource<Value: Decodable>: ObservableObject {
    enum Phase {
        case loading
        case loaded(Value)
        case failed
    }

    @Published private(set) var phase: Phase = .loading
    private let api: APIClient?
    private let path: String

    init(api: APIClient?, path: String) {
        self.api = api
        self.path = path
    }

    var hasLoaded: Bool {
        if case .loaded = phase { return true }
        return false
    }

    var value: Value? {
        if case .loaded(let loaded) = phase { return loaded }
        return nil
    }

    /// Primera carga con indicador; las siguientes (por eventos) refrescan sin borrar lo que ya se ve.
    func reload() async { await load(showSpinner: !hasLoaded) }

    func load(showSpinner: Bool = true) async {
        guard let api else {
            phase = .failed
            return
        }
        if showSpinner { phase = .loading }
        do {
            let loaded = try await api.get(path, as: Value.self)
            phase = .loaded(loaded)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // Si ya había datos se conservan; el error solo se muestra cuando no hay nada que enseñar.
            if !hasLoaded { phase = .failed }
        }
    }
}

/// Estado de una escritura (POST o PATCH) que se confirma en una hoja: ocupado, error o conflicto de versión.
@MainActor
final class ActionModel: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    /// 409 por versión: el registro cambió y no se guardó nada.
    @Published private(set) var conflict = false

    func fail(_ message: String) {
        error = message
        conflict = false
    }

    /// Ejecuta la escritura; devuelve `true` si terminó bien.
    func run(_ operation: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        error = nil
        conflict = false
        defer { busy = false }
        do {
            try await operation()
            return true
        } catch is CancellationError {
            return false
        } catch let failure as ClientError {
            conflict = failure.isVersionConflict
            error = failure.localizedDescription
            return false
        } catch {
            self.error = "No se pudo completar la operación. Revisa tu conexión e inténtalo de nuevo."
            return false
        }
    }
}
