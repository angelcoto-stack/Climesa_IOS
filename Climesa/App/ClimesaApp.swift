import SwiftUI

@main
struct ClimesaApp: App {
    init() { Appearance.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()   // el esquema de color (barra de estado) lo decide RootView
        }
    }
}
