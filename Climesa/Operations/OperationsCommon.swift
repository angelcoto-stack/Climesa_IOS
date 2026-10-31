import SwiftUI

/// Cargando, error con reintento o el contenido, según el estado de un recurso.
struct ResourceContent<Value: Decodable, Content: View>: View {
    @ObservedObject var resource: RemoteResource<Value>
    let loadingText: String
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        Group {
            switch resource.phase {
            case .loading:
                VStack(alignment: .leading, spacing: 18) {
                    ProgressView().tint(Theme.blue)
                    Text(loadingText).font(.system(size: 11)).foregroundColor(Theme.muted)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 120)
                .frame(maxWidth: .infinity, alignment: .leading)

            case .failed:
                VStack(alignment: .leading, spacing: 16) {
                    Banner(kind: .error, text: "No se pudo cargar la información. Revisa tu conexión e inténtalo de nuevo.")
                    PrimaryButton(title: "Volver a intentar") { Task { await resource.load() } }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

            case .loaded(let value):
                content(value)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Dato con su etiqueta, una por línea.
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10.5)).foregroundColor(Theme.muted)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Fila de navegación del listado de gestión en Perfil / Más.
struct ManagementRow: View {
    let section: ManagementSection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol).font(.system(size: 15)).foregroundColor(Theme.blue)
            Text(section.title).font(.system(size: 13.5)).foregroundColor(Theme.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.muted)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// Pantalla de cada sección de gestión. Vuelve a comprobar el permiso: sin él no se pide nada a la API.
struct ManagementDestination: View {
    let section: ManagementSection
    let user: UserProfile
    let api: APIClient?
    /// Sube con cada evento en vivo; las pantallas vuelven a pedir sus datos con él.
    let liveVersion: Int

    var body: some View {
        Group {
            if user.access.hasPermission(section.requiredPermission) {
                switch section {
                case .ambulancia:
                    AmbulanceView(user: user, api: api, liveVersion: liveVersion)
                case .planificacion:
                    ShiftPlanningView(user: user, api: api, liveVersion: liveVersion)
                case .personal:
                    StaffDirectoryView(user: user, api: api, liveVersion: liveVersion)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Banner(kind: .error, text: "Tu cuenta no tiene acceso a esta sección.")
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .background(Theme.background)
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
