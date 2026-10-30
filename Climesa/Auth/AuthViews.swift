import SwiftUI

// MARK: - Raíz

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel

    /// Las cuentas con rol Médico o Paciente con acceso a iOS (según la API) usan el shell claro.
    /// Lo decide `TabPolicy` con el perfil verificado de /auth/me.
    private var shellUser: UserProfile? {
        guard case .signedIn(let user) = auth.state else { return nil }
        switch TabPolicy.decide(user.access) {
        case .tabs: return user
        case .unsupportedRole: return nil
        }
    }

    var body: some View {
        Group {
            if let user = shellUser {
                ShellRoot(user: user, services: auth.services)
                    .id(user.id)
            } else {
                legacyContainer
            }
        }
        .background(Theme.background.ignoresSafeArea())
        // Barra de estado: clara sobre el encabezado navy, oscura sobre el shell claro.
        .preferredColorScheme(shellUser != nil ? .light : .dark)
        .task { await auth.restoreSession() }
    }

    private var legacyContainer: some View {
        VStack(spacing: 0) {
            ClimesaHeader {
                if case .signedIn(let user) = auth.state {
                    AccountMenu(user: user) { auth.logout() }
                }
            }
            Group {
                switch auth.state {
                case .checking:
                    CheckingView()
                case .connectionError:
                    ConnectionErrorView()
                case .signedOut:
                    AuthFlowView()
                case .signedIn:
                    // Solo llega aquí una cuenta cuyo rol no usa iOS (por ejemplo Recepción).
                    UnsupportedRoleView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .light)
        }
    }
}

struct AccountMenu: View {
    let user: UserProfile
    let onLogout: () -> Void

    var body: some View {
        Menu {
            Text(user.name)
            Button(role: .destructive, action: onLogout) {
                Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 20))
                .foregroundColor(.white)
        }
    }
}

/// Rol sin iOS (por ejemplo Recepción): solo puede salir.
struct UnsupportedRoleView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeadlineText(text: L.text("unsupported.title")).padding(.top, 90)
            BodyText(text: L.text("unsupported.body")).padding(.top, 24)
            LinkButton(title: L.text("common.logout")) { auth.logout() }
                .padding(.top, 28)
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
// MARK: - Formularios de acceso

struct AuthFlowView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        switch auth.screen {
        case .login: LoginView()
        case .register: RegisterView()
        }
    }
}

/// iOS / Acceso / Ingreso · Error de ingreso · Confirmación · Validando credenciales
struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @FocusState private var focus: AuthField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel(text: "ACCESO PERSONAL / 01").padding(.top, 24)
                HeadlineText(text: "Buen día.\nTu jornada\ncomienza aquí.").padding(.top, 20)
                BodyText(text: "Ingresa con tu cuenta del hospital.").padding(.top, 24)

                if let error = auth.errorMessage {
                    Banner(kind: .error, text: error).padding(.top, 24)
                }
                if let info = auth.infoMessage {
                    Banner(kind: .info, text: info).padding(.top, 24)
                }

                FormCard {
                    ClimesaField(label: "Correo electrónico", text: $auth.email, prompt: "tu@correo.com",
                                 keyboard: .emailAddress, contentType: .username, field: .email, focus: $focus)
                    ClimesaField(label: "Contraseña", text: $auth.password, prompt: "••••••••",
                                 secure: true, contentType: .password, field: .password, focus: $focus)
                }
                .padding(.top, 24)

                PrimaryButton(title: auth.isLoading ? "Ingresando…" : "Ingresar", isEnabled: !auth.isLoading) {
                    focus = nil
                    Task { await auth.login() }
                }
                .padding(.top, 20)

                LinkButton(title: "¿Eres paciente? Crear cuenta") { auth.showRegister() }
                    .padding(.top, 28)

                Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 40)
                Text("Tu cuenta es personal. Cierra sesión al terminar.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.muted)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
    }
}

/// iOS / Acceso / Registro de paciente · Error de registro
struct RegisterView: View {
    @EnvironmentObject var auth: AuthViewModel
    @FocusState private var focus: AuthField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel(text: "CUENTA DE PACIENTE / 01").padding(.top, 24)
                HeadlineText(text: "Tu salud,\nmás cerca.").padding(.top, 20)
                BodyText(text: "Crea tu cuenta para acceder a tus servicios.").padding(.top, 24)

                if let error = auth.errorMessage {
                    Banner(kind: .error, text: error).padding(.top, 24)
                }

                FormCard {
                    ClimesaField(label: "Nombre completo", text: $auth.name, prompt: "",
                                 contentType: .name, capitalization: .words, field: .name, focus: $focus)
                    ClimesaField(label: "Correo electrónico", text: $auth.email, prompt: "tu@correo.com",
                                 keyboard: .emailAddress, contentType: .emailAddress, field: .email, focus: $focus)
                    ClimesaField(label: "Contraseña", text: $auth.password, prompt: "••••••••",
                                 secure: true, contentType: .newPassword, field: .password, focus: $focus)
                    ClimesaField(label: "Confirmar contraseña", text: $auth.confirm, prompt: "••••••••",
                                 secure: true, contentType: .newPassword, field: .confirm, focus: $focus)
                    Text("8 caracteres, mayúscula, minúscula, número y símbolo.")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
                .padding(.top, 24)

                PrimaryButton(title: auth.isLoading ? "Creando cuenta…" : "Crear cuenta", isEnabled: !auth.isLoading) {
                    focus = nil
                    Task { await auth.register() }
                }
                .padding(.top, 20)

                LinkButton(title: "¿Ya tienes cuenta? Ingresar") { auth.showLogin() }
                    .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            focus = .name
        }
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
    }
}

// MARK: - Estados de sesión

/// iOS / Acceso / Comprobando
struct CheckingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lock")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(Theme.blue)
            Text("Verificando tu acceso…")
                .font(.system(size: 13))
                .foregroundColor(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// iOS / Acceso / Verificación fallida
struct ConnectionErrorView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeadlineText(text: "Tu acceso.").padding(.top, 90)
            BodyText(text: "Revisa tu conexión e intenta de nuevo.").padding(.top, 24)
            PrimaryButton(title: "Volver a intentar") {
                Task { await auth.restoreSession() }
            }
            .padding(.top, 24)
            LinkButton(title: "Cerrar sesión") { auth.logout() }
                .padding(.top, 28)
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
