import SwiftUI

/// Estado de sesión de la app. Ingresa, registra y renueva con Supabase Auth (REST) y verifica
/// el perfil, los permisos y las plataformas con GET /auth/me. La sesión vive en el Keychain.
@MainActor
final class AuthViewModel: ObservableObject {
    enum SessionState {
        case checking, signedOut, signedIn(UserProfile), connectionError
    }
    enum Screen { case login, register }

    @Published var state: SessionState = .checking
    @Published var screen: Screen = .login

    @Published var email = ""
    @Published var password = ""
    @Published var name = ""
    @Published var confirm = ""

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    /// nil si falta o es inválida la configuración (Configuration.plist).
    let services: ClientServices?
    /// Sube al cerrar sesión para descartar respuestas de operaciones que quedaron en vuelo.
    private var revision = 0

    init() {
        do {
            services = ClientServices(config: try AppConfiguration.load())
        } catch {
            services = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Sesión

    func restoreSession() async {
        guard let services else {
            state = .connectionError
            return
        }
        let stamp = revision
        state = .checking
        do {
            guard try await services.auth.session() != nil else {
                guard stamp == revision else { return }
                state = .signedOut
                return
            }
            let profile = try await loadProfile()
            guard stamp == revision else { return }
            state = .signedIn(profile)
        } catch {
            guard stamp == revision else { return }
            await settleAfterFailure()
        }
    }

    /// "Actualizar acceso": vuelve a verificar roles y permisos contra la API sin pasar por la pantalla de carga.
    func refreshAccess() async -> Bool {
        guard case .signedIn = state else { return false }
        let stamp = revision
        do {
            let profile = try await loadProfile()
            guard stamp == revision else { return false }
            state = .signedIn(profile)
            return true
        } catch {
            // Si la API cerró la sesión (401), la pantalla vuelve al ingreso; si solo falló la red, se conserva.
            let stored = await hasSession()
            if stamp == revision, !stored {
                state = .signedOut
            }
            return false
        }
    }

    /// Cierra la sesión de inmediato en pantalla; el aviso a Supabase y el borrado del Keychain siguen en segundo plano.
    func logout() {
        revision += 1
        let auth = services?.auth
        resetFields()
        screen = .login
        state = .signedOut
        Task { await auth?.signOut() }
    }

    private func loadProfile() async throws -> UserProfile {
        guard let services else { throw ClientError.message("Falta configurar el servidor de Climesa.") }
        let access = try await services.api.get("/auth/me", as: AccessProfile.self)
        return UserProfile(access: access)
    }

    /// Tras un fallo de verificación: sin sesión guardada se vuelve al ingreso; con sesión, se ofrece reintentar.
    private func settleAfterFailure() async {
        let stored = await hasSession()
        state = stored ? .connectionError : .signedOut
    }

    private func hasSession() async -> Bool {
        guard let auth = services?.auth else { return false }
        return (try? await auth.session()) != nil
    }

    private func message(for error: Error) -> String {
        if error is URLError { return "Sin conexión. Revisa tu conexión e intenta de nuevo." }
        return error.localizedDescription
    }

    // MARK: Navegación entre formularios

    func showRegister() {
        errorMessage = nil
        infoMessage = nil
        password = ""
        screen = .register
    }

    func showLogin() {
        errorMessage = nil
        infoMessage = nil
        password = ""
        confirm = ""
        screen = .login
    }

    // MARK: Ingreso

    func login() async {
        errorMessage = nil
        infoMessage = nil
        guard !email.trimmed.isEmpty, !password.isEmpty else {
            errorMessage = "Escribe tu correo y tu contraseña."
            return
        }
        guard let services else {
            errorMessage = "Falta configurar el servidor de Climesa."
            return
        }
        let stamp = revision
        isLoading = true
        defer { isLoading = false }
        do {
            try await services.auth.signIn(email: email, password: password)
            let profile = try await loadProfile()
            guard stamp == revision else { return }
            password = ""
            state = .signedIn(profile)
        } catch is CancellationError {
            return
        } catch {
            guard stamp == revision else { return }
            errorMessage = message(for: error)
        }
    }

    // MARK: Registro

    func register() async {
        errorMessage = nil
        infoMessage = nil

        let problems = RegistrationRules.errors(name: name, email: email.trimmed, password: password, confirmation: confirm)
        guard problems.isEmpty else {
            errorMessage = "Revisa los datos. " + problems.joined(separator: " ")
            return
        }
        guard let services else {
            errorMessage = "Falta configurar el servidor de Climesa."
            return
        }

        let stamp = revision
        isLoading = true
        defer { isLoading = false }
        do {
            let signedIn = try await services.auth.signUp(name: name, email: email, password: password)
            guard stamp == revision else { return }
            if signedIn {
                let profile = try await loadProfile()
                guard stamp == revision else { return }
                clearRegistrationFields()
                state = .signedIn(profile)
            } else {
                clearRegistrationFields()
                screen = .login
                infoMessage = "Revisa tu correo para confirmar tu cuenta. Después podrás ingresar."
            }
        } catch is CancellationError {
            return
        } catch {
            guard stamp == revision else { return }
            errorMessage = message(for: error)
        }
    }

    private func clearRegistrationFields() {
        password = ""
        confirm = ""
        name = ""
    }

    private func resetFields() {
        email = ""
        password = ""
        name = ""
        confirm = ""
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: Tiempo real

    /// Servicio de tiempo real con el token vigente de la sesión. Los datos llegan empujados; tras una caída
    /// hace UNA consulta de recuperación a /eventos?after= (no hay sondeo periódico).
    func makeRealtime() -> (any RealtimeService)? {
        guard let services else { return nil }
        let auth = services.auth
        let api = services.api
        let url = RealtimeProtocol.websocketURL(supabaseURL: services.config.supabase.absoluteString,
                                                publishableKey: services.config.publicKey)
        return SupabaseRealtimeService(
            websocketURL: url,
            accessToken: { (try? await auth.session())?.access_token },
            catchUp: { cursor in
                let data = try await api.getData(RealtimeProtocol.catchUpPath(after: cursor))
                guard let recovered = RealtimeProtocol.parseCatchUp(data: data) else {
                    throw ClientError.message("No se pudo recuperar lo ocurrido sin conexión.")
                }
                return recovered
            },
            // Sin `after`, la API devuelve el cursor actual: es el punto de partida de la recuperación.
            head: {
                let data = try await api.getData("/eventos")
                guard let current = RealtimeProtocol.parseCatchUp(data: data) else {
                    throw ClientError.message("No se pudo leer el cursor de eventos.")
                }
                return current.cursor
            },
            sockets: URLSessionRealtimeSocketFactory()
        )
    }
}
