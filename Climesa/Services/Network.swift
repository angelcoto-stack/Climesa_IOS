import Foundation

/// Error con un mensaje ya listo para mostrar a la persona.
enum ClientError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(text) = self { return text }
        return nil
    }
}

/// Configuración pública leída de `Configuration.plist` (URL de Supabase, clave publicable y URL de la API).
/// La clave publicable es pública por diseño; aquí nunca van contraseñas ni claves secretas.
struct AppConfiguration {
    let supabase: URL
    let publicKey: String
    let api: URL

    static func load() throws -> AppConfiguration {
        guard let url = Bundle.main.url(forResource: "Configuration", withExtension: "plist"),
              let bytes = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: String],
              let auth = values["SupabaseURL"].flatMap({ URL(string: $0) }),
              let key = values["SupabasePublishableKey"], !key.isEmpty,
              let apiValue = values["ClimesaAPIBaseURL"], let api = URL(string: apiValue), api.host != nil
        else { throw ClientError.message("Falta configurar el servidor de Climesa.") }
        #if DEBUG
        guard api.scheme == "https" || (["localhost", "127.0.0.1"].contains(api.host ?? "") && api.scheme == "http") else {
            throw ClientError.message("Utiliza HTTPS o el servidor local de desarrollo.")
        }
        #else
        guard api.scheme == "https" else {
            throw ClientError.message("La versión de entrega requiere un servidor HTTPS.")
        }
        #endif
        return AppConfiguration(supabase: auth, publicKey: key, api: api)
    }
}

/// Supabase Auth por REST: ingreso, registro, renovación y cierre de sesión. La sesión vive en el Keychain.
actor AuthService {
    private let transport = URLSession(configuration: .ephemeral)
    private let config: AppConfiguration
    private var revision = 0
    private var refreshTask: Task<AuthSession, Error>?

    init(config: AppConfiguration) { self.config = config }

    private func send(_ path: String, _ body: [String: Any], token: String? = nil) async throws -> Data {
        guard let url = URL(string: config.supabase.absoluteString + path) else {
            throw ClientError.message("Configuración de acceso inválida.")
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(config.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClientError.message("No se pudo autenticar. Revisa los datos y la activación de tu cuenta, o inténtalo más tarde.")
        }
        return data
    }

    private func parse(_ data: Data) throws -> AuthSession {
        // expires_at se calcula cuando la respuesta del proveedor incluye solo expires_in.
        var json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if json["expires_at"] == nil {
            json["expires_at"] = Date().timeIntervalSince1970 + (json["expires_in"] as? Double ?? 3600)
        }
        return try JSONDecoder().decode(AuthSession.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func signIn(email: String, password: String) async throws {
        let stamp = revision
        let data = try await send("/auth/v1/token?grant_type=password",
                                  ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
        let session = try parse(data)
        guard stamp == revision else { throw CancellationError() }
        try KeychainStore.save(session)
    }

    /// Devuelve `true` si la cuenta quedó con sesión; `false` si hay que confirmar el correo primero.
    func signUp(name: String, email: String, password: String) async throws -> Bool {
        let stamp = revision
        let data = try await send("/auth/v1/signup", [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "data": ["nombre": name.trimmingCharacters(in: .whitespacesAndNewlines)]
        ])
        guard stamp == revision else { throw CancellationError() }
        if let session = try? parse(data) {
            try KeychainStore.save(session)
            return true
        }
        return false
    }

    /// Sesión vigente: renueva con el refresh token cuando falta menos de un minuto para que venza.
    func session() async throws -> AuthSession? {
        if let task = refreshTask { return try await task.value }
        guard let saved = try KeychainStore.load() else { return nil }
        if saved.expires_at > Date().timeIntervalSince1970 + 60 { return saved }
        let stamp = revision
        let task = Task<AuthSession, Error> {
            let next = try self.parse(await self.send("/auth/v1/token?grant_type=refresh_token",
                                                       ["refresh_token": saved.refresh_token]))
            guard stamp == self.revision else { throw CancellationError() }
            try KeychainStore.save(next)
            return next
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func signOut() async {
        revision += 1
        refreshTask?.cancel()
        refreshTask = nil
        let saved = try? KeychainStore.load()
        KeychainStore.clear()
        if let saved { _ = try? await send("/auth/v1/logout?scope=local", [:], token: saved.access_token) }
    }
}

/// application/problem+json (`detail`) con respaldo al formato anterior `error.message`.
private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String? }
    let detail: String?
    let error: Detail?
    var text: String? { detail ?? error?.message }
}

/// Cliente de la API de Climesa. Solo lee: /auth/me, /turnos/mios y /eventos.
actor APIClient {
    private let transport = URLSession(configuration: .ephemeral)
    private let config: AppConfiguration
    private let auth: AuthService

    init(config: AppConfiguration, auth: AuthService) {
        self.config = config
        self.auth = auth
    }

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await getData(path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Respuesta cruda de un GET autenticado; la usa también la recuperación de eventos de tiempo real.
    func getData(_ path: String) async throws -> Data {
        guard let session = try await auth.session() else { throw ClientError.message("Inicia sesión para continuar.") }
        let base = config.api.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw ClientError.message("Servidor inválido.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer \(session.access_token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.message("El servidor no respondió.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                await auth.signOut()
                throw ClientError.message("Tu sesión no está activa. Vuelve a ingresar.")
            }
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.text
            throw ClientError.message(message ?? "No se pudo consultar la información. Vuelve a intentar.")
        }
        return data
    }
}

/// Servicios de red ya construidos con la configuración vigente.
struct ClientServices {
    let config: AppConfiguration
    let auth: AuthService
    let api: APIClient

    init(config: AppConfiguration) {
        let auth = AuthService(config: config)
        self.config = config
        self.auth = auth
        self.api = APIClient(config: config, auth: auth)
    }
}
