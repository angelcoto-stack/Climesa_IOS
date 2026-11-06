
import Foundation

/// Estados permitidos para una orden de laboratorio.
public enum LabProgress: String, Codable, CaseIterable, Sendable {
    case pending = "Pendiente"
    case processing = "En Proceso"
    case complete = "Completado"

    public func canTransition(to next: LabProgress) -> Bool {
        switch (self, next) {
        case (.pending, .processing),
             (.processing, .complete):
            return true
        default:
            return false
        }
    }
}
