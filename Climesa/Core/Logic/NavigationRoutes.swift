import Foundation

/// Tabla de rutas de la navegación de Médico y Paciente (lógica pura, sin UI).
/// Una arista dice desde qué nodo se llega a una pantalla y qué permiso exige (`nil`: ninguno).
/// Nodos: `raiz` (ingreso), `tab.<pestaña>` (`AppTab`), `mi-atencion` (sección de Mi cuenta solo para paciente)
/// y los IDs de pantalla de pantallas.csv. Los permisos son los de `permisos.csv` y coinciden con `FlowVisibility`.
/// La prueba `NavigationRoutesTests` comprueba que ninguna pantalla iOS de MED o PAC queda inalcanzable.
public enum NavigationRoutes {
    public static let root = "raiz"
    public static let patientCareSection = "mi-atencion"

    public static func tabNode(_ tab: AppTab) -> String { "tab.\(tab.rawValue)" }

    public struct Edge: Equatable, Sendable {
        public let from: String
        public let to: String
        public let permission: String?

        public init(from: String, to: String, permission: String? = nil) {
            self.from = from
            self.to = to
            self.permission = permission
        }
    }

    /// Pantallas iOS de pantallas.csv para Médico y Paciente (I01 a I13 y I20 a I26).
    public static let iosScreens: [String] = [
        "I01", "I02", "I03", "I04", "I05", "I06", "I07", "I08", "I09", "I10", "I11", "I12", "I13",
        "I20", "I21", "I22", "I23", "I24", "I25", "I26"
    ]

    public static let edges: [Edge] = [
        // Ingreso y registro de paciente
        Edge(from: NavigationRoutes.root, to: "I01"),
        Edge(from: "I01", to: "I02"),

        // Pestañas de Paciente
        Edge(from: NavigationRoutes.tabNode(.inicio), to: "I04"),
        Edge(from: NavigationRoutes.tabNode(.fila), to: "I05", permission: "fila.ver"),
        Edge(from: NavigationRoutes.tabNode(.citas), to: "I06", permission: "citas.ver"),
        Edge(from: NavigationRoutes.tabNode(.examenes), to: "I07", permission: "resultados.ver"),
        Edge(from: NavigationRoutes.tabNode(.mas), to: "I12"),
        Edge(from: NavigationRoutes.tabNode(.mas), to: NavigationRoutes.patientCareSection),
        Edge(from: NavigationRoutes.patientCareSection, to: "I03", permission: "cuenta.vincular"),
        Edge(from: NavigationRoutes.patientCareSection, to: "I08", permission: "expediente.ver"),
        Edge(from: NavigationRoutes.patientCareSection, to: "I09", permission: "ambulancia.solicitar"),
        Edge(from: NavigationRoutes.patientCareSection, to: "I11", permission: "auditoria.mis_accesos"),
        Edge(from: NavigationRoutes.patientCareSection, to: "I13"),

        // Pestañas de Médico
        Edge(from: NavigationRoutes.tabNode(.miDia), to: "I20"),
        Edge(from: "I20", to: "I21", permission: "consulta.iniciar"),
        Edge(from: "I20", to: "I22", permission: "expediente.ver"),
        Edge(from: "I20", to: "I23", permission: "resultados.ver"),
        Edge(from: "I20", to: "I24", permission: "admision.ver"),
        Edge(from: "I20", to: "I25", permission: "ambulancia.recibir_prehospital"),
        Edge(from: NavigationRoutes.tabNode(.resultados), to: "I23", permission: "resultados.ver"),
        Edge(from: NavigationRoutes.tabNode(.turnos), to: "I26", permission: "turnos.ver"),
        Edge(from: NavigationRoutes.tabNode(.perfil), to: "I12"),

        // Hospital: sección de la cuenta, visible para ambos roles
        Edge(from: "I12", to: "I10")
    ]

    /// Nodos alcanzables con el perfil verificado: la raíz, las pestañas que `TabPolicy` le da y lo que abren sus permisos.
    public static func reachable(for profile: AccessProfile) -> Set<String> {
        var start: Set<String> = [root]
        if case let .tabs(_, tabs) = TabPolicy.decide(profile) {
            for tab in tabs { start.insert(tabNode(tab)) }
        }
        var visited = start
        var pending = Array(start)
        while let node = pending.popLast() {
            for edge in edges where edge.from == node {
                if let code = edge.permission, !profile.hasPermission(code) { continue }
                if visited.insert(edge.to).inserted { pending.append(edge.to) }
            }
        }
        return visited
    }

    /// Pantallas de `iosScreens` sin ruta para el perfil dado.
    public static func unreachableScreens(for profile: AccessProfile) -> [String] {
        let reachable = reachable(for: profile)
        return iosScreens.filter { !reachable.contains($0) }
    }
}