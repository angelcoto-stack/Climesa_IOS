import SwiftUI

@main
struct ClimesaApp: App {
    @StateObject private var auth = AuthViewModel()
    @Environment(\.scenePhase) private var phase
    @State private var leftAt: Date?

    init() { Appearance.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()   // el esquema de color (barra de estado) lo decide RootView
                .environmentObject(auth)
                .onChange(of: phase) { value in
                    if value == .background {
                        leftAt = Date()
                    } else if value == .active, let since = leftAt {
                        leftAt = nil
                        // Más de 5 minutos en segundo plano cierra la sesión; si no, se revalida el acceso.
                        if Date().timeIntervalSince(since) > 300 {
                            auth.logout()
                        } else {
                            Task { _ = await auth.refreshAccess() }
                        }
                    }
                }
        }
    }
}
