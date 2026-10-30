import Foundation
import Security
struct AuthSession: Codable { let access_token: String; let refresh_token: String; let expires_at: TimeInterval; let user: AuthUser }
struct AuthUser: Codable { let id: String; let email: String? }
enum KeychainStore {
    static let service = "edu.climesa.app.session"
    static var query: [String: Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"current"] }
    static func load() throws -> AuthSession? {
        var request=query; request[kSecReturnData as String]=true; request[kSecMatchLimit as String]=kSecMatchLimitOne
        var value: CFTypeRef?
        let status=SecItemCopyMatching(request as CFDictionary,&value)
        if status==errSecItemNotFound { return nil }
        guard status==errSecSuccess, let bytes=value as? Data else { throw ClientError.message("No se pudo recuperar la sesión de forma segura.") }
        return try JSONDecoder().decode(AuthSession.self,from:bytes)
    }
    static func save(_ session: AuthSession) throws {
        let data=try JSONEncoder().encode(session)
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status==errSecItemNotFound {
            var item=query; item[kSecValueData as String]=data; item[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else { throw ClientError.message("No se pudo guardar la sesión de forma segura.") }; return
        }
        guard status==errSecSuccess else { throw ClientError.message("No se pudo actualizar la sesión de forma segura.") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
