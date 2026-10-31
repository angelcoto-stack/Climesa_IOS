import Foundation

/// Transporte real sobre URLSessionWebSocketTask. Cada `open` crea un socket nuevo con su propio flujo de eventos.
public struct URLSessionRealtimeSocketFactory: RealtimeSocketFactory {
    public init() {}
    public func open(url: String) -> RealtimeSocket { URLSessionRealtimeSocket(urlString: url) }
}

final class URLSessionRealtimeSocket: NSObject, RealtimeSocket, URLSessionWebSocketDelegate, @unchecked Sendable {
    let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    init(urlString: String) {
        var captured: AsyncStream<SocketEvent>.Continuation?
        events = AsyncStream(SocketEvent.self) { captured = $0 }
        continuation = captured!
        super.init()
        guard let url = URL(string: urlString) else {
            continuation.yield(.closed("Dirección de tiempo real inválida."))
            continuation.finish()
            return
        }
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.continuation.yield(.text(text))
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.continuation.yield(.text(text)) }
                @unknown default:
                    break
                }
                self.receive()
            case .failure(let error):
                self.continuation.yield(.closed(error.localizedDescription))
                self.continuation.finish()
            }
        }
    }

    func send(_ text: String) async -> Bool {
        guard let task else { return false }
        do {
            try await task.send(.string(text))
            return true
        } catch {
            return false
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        continuation.finish()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol negotiatedProtocol: String?) {
        continuation.yield(.opened)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        continuation.yield(.closed(nil))
        continuation.finish()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation.yield(.closed(error.localizedDescription)) }
        continuation.finish()
    }
}
