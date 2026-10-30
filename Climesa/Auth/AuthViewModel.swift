import SwiftUI

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

    private let backend = HospitalBackend.shared
    private let sessionKey = "climesa.session.userId"

    // MARK: Sesión

    func restoreSession() async {
        guard let raw = UserDefaults.standard.string(forKey: sessionKey),
              let id = UUID(uuidString: raw) else {
            state = .signedOut
            return
        }
        state = .checking
        do {
            if let profile = try await backend.validateSession(userId: id) {
                state = .signedIn(profile)
            } else {
                clearSession()
                state = .signedOut
            }
        } catch {
            state = .connectionError
        }
    }

    /// "Actualizar acceso": vuelve a validar la cuenta (roles y estado) contra el backend.
    func refreshAccess() async -> Bool {
        guard case .signedIn(let current) = state else { return false }
        do {
            if let profile = try await backend.validateSession(userId: current.id) {
                state = .signedIn(profile)
                return true
            }
            logout()
            return false
        } catch {
            return false
        }
    }

    func logout() {
        clearSession()
        resetFields()
        screen = .login
        state = .signedOut
    }

    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
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
            errorMessage = BackendError.invalidCredentials.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await backend.login(email: email, password: password)
            UserDefaults.standard.set(profile.id.uuidString, forKey: sessionKey)
            password = ""
            state = .signedIn(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Registro

    static func isStrongPassword(_ p: String) -> Bool {
        p.count >= 8
            && p.rangeOfCharacter(from: .uppercaseLetters) != nil
            && p.rangeOfCharacter(from: .lowercaseLetters) != nil
            && p.rangeOfCharacter(from: .decimalDigits) != nil
            && p.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted.subtracting(.whitespaces)) != nil
    }

    private static func isValidEmail(_ e: String) -> Bool {
        let parts = e.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !e.contains(" ")
    }

    func register() async {
        errorMessage = nil
        infoMessage = nil

        guard !name.trimmed.isEmpty else {
            errorMessage = "Revisa los datos. Escribe tu nombre completo."
            return
        }
        guard Self.isValidEmail(email.trimmed) else {
            errorMessage = "Revisa los datos. El correo no es válido."
            return
        }
        guard password == confirm else {
            errorMessage = "Revisa los datos. Las contraseñas deben coincidir."
            return
        }
        guard Self.isStrongPassword(password) else {
            errorMessage = "Revisa los datos. La contraseña debe tener 8 caracteres, mayúscula, minúscula, número y símbolo."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            try await backend.register(name: name, email: email, password: password)
            password = ""
            confirm = ""
            name = ""
            screen = .login
            infoMessage = "Revisa tu correo. Si necesitas confirmarlo, recibirás un enlace para activar tu cuenta."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetFields() {
        email = ""
        password = ""
        name = ""
        confirm = ""
        errorMessage = nil
        infoMessage = nil
    }
}
