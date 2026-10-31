# Climesa · Hospital universitario (iOS, SwiftUI)

App iOS nativa (Swift / SwiftUI, iOS 16+, Xcode 15+) del proyecto integrador. Arquitectura **MVVM** con `async/await`.
El diseño visual (Theme, pantallas de acceso y shell con barra inferior) es el del equipo de iOS; por debajo ya usa la
**API real** de Climesa y Supabase Auth. No queda ningún backend simulado.

## Estado honesto

- Compilado y probado en un iPhone físico: **la versión anterior** (con datos simulados). Esta rama (`feat/conexion-api-supabase`)
  se escribió sin Mac ni Xcode: **todavía no se ha compilado ni probado en dispositivo**. Hace falta compilar en Mac/Xcode,
  corregir lo que salga y probar en el iPhone antes de darla por buena.
- El flujo de integración continua (`.github/workflows/build-ipa.yml`) ejecuta `swift test` (lógica pura) y luego
  compila un `.ipa` **sin firmar** (`CODE_SIGNING_ALLOWED=NO`). Sirve para comprobar que compila, no para instalar en el teléfono.
- Para instalar en el iPhone hay que firmar desde Xcode con tu Apple ID (bundle id `edu.climesa.app`, iOS 16.0 mínimo).

## Qué se conecta a la API real

| Función | Cómo |
|---|---|
| Ingreso, registro, renovación y cierre de sesión | Supabase Auth por REST (`Climesa/Services/Network.swift`, `AuthService`) |
| Sesión | Keychain (`KeychainStore.swift`), nunca `UserDefaults` |
| Perfil, roles, permisos y plataformas | `GET /auth/me` |
| Pestañas por rol y permisos | `TabPolicy` (`Climesa/Core/Logic/Access.swift`) |
| Mis turnos (Médico) | `GET /turnos/mios`, se vuelve a pedir solo al entrar y cuando llega un evento de turnos |
| Cambios en vivo | Supabase Realtime (WebSocket) + una consulta de recuperación `GET /eventos?after=` tras una caída. Sin sondeo periódico |
| Banda de conexión | "Reconectando…" / "Sin conexión" según el estado del tiempo real |
| Cierre por inactividad | Más de 5 minutos en segundo plano cierra la sesión (`ClimesaApp.swift`) |

Médico ve: Mi día, Pacientes, Resultados, Turnos, Perfil. Paciente ve: Inicio, Fila, Citas, Exámenes, Más.
Solo **Turnos** y **Perfil/Más** tienen datos; el resto muestra "Este módulo todavía no está habilitado".
Cualquier otro rol (por ejemplo Recepción) ve "Tu rol no usa esta aplicación" y solo puede cerrar sesión.

El registro desde la app crea una cuenta de paciente; si el proyecto exige confirmar el correo, se avisa y la persona
ingresa después de confirmar.

## Configuración

Todo está en `Climesa/Configuration.plist` (se copia al bundle):

| Clave | Valor por defecto |
|---|---|
| `SupabaseURL` | URL pública del proyecto de Supabase |
| `SupabasePublishableKey` | clave **publicable** (es pública por diseño) |
| `ClimesaAPIBaseURL` | `https://sghu-api.onrender.com/api/v1` |

Para apuntar a otra API cambia `ClimesaAPIBaseURL`. En Release solo se acepta HTTPS; en Debug también
`http://localhost` o `http://127.0.0.1`. En una API gratuita de Render la primera petición puede tardar mientras despierta.
Nunca pongas contraseñas ni claves secretas en el repositorio.

## Cómo ejecutar

1. Abre **`Climesa.xcodeproj`** en Xcode 15 o superior.
2. Elige un simulador o tu iPhone y, si Xcode lo pide, Signing & Capabilities → Team → tu Apple ID.
3. Pulsa **▶ (Cmd+R)** e ingresa con una cuenta real de Climesa.

## Pruebas

Hay 89 pruebas XCTest en `Tests/CoreTests` (`swift test` en la raíz del repositorio, macOS; el CI de GitHub Actions en macos-15 las ejecuta en cada PR). Cubren solo lógica pura, sin red ni UI, con datos ficticios:

- `AccessTests`, `TabPolicyTests`: roles, permisos, pestañas por rol y su orden, decodificación del perfil de `/auth/me`.
- `RegistrationRulesTests`: nombre, correo, contraseña y confirmación, con sus límites.
- `RealtimeProtocolTests`, `RealtimeProtocolEdgeTests`: armado y lectura de marcos Phoenix, texto malformado, respuestas de error, recuperación de eventos.
- `SupabaseRealtimeServiceTests`: servicio de tiempo real con un socket de prueba (uniones, latido, reconexión con espera creciente hasta 30 s, recuperación paginada, token nuevo por conexión).

Queda manual en el iPhone (el CI no lo comprueba): ingreso real con Supabase Auth, llegada de eventos por el WebSocket real, recuperación tras perder y recuperar la red, vista de Mis turnos con datos reales (fechas y zona horaria), Keychain, cierre de sesión a los 5 minutos en segundo plano, diseño y accesibilidad.

`project.yml` es opcional (XcodeGen); el proyecto ya incluye todos los archivos.

## Estructura

```
Climesa/
  App/ClimesaApp.swift                 sesión, cierre a los 5 min en segundo plano
  Auth/AuthViewModel.swift             estados de sesión sobre Supabase Auth + /auth/me
  Auth/AuthViews.swift                 raíz, ingreso, registro, comprobando, error de conexión, rol sin iOS
  Shell/ShellViews.swift               pestañas por rol, turnos, cuenta, banda de conexión
  Core/Theme.swift                     diseño del equipo de iOS
  Core/Logic/Access.swift              perfil, TabPolicy, reglas de registro (puro, con pruebas)
  Core/Logic/Realtime/                 protocolo Phoenix, servicio de tiempo real, estado en vivo (puro, con pruebas)
  Services/Network.swift               configuración, AuthService, APIClient
  Services/KeychainStore.swift         sesión en el Keychain
  Services/LiveViewModel.swift         estado de tiempo real para las vistas
  Models/Models.swift                  Area, UserProfile, turnos
  Configuration.plist · Localizable.xcstrings
Tests/CoreTests/                       pruebas de Core/Logic
Package.swift                          paquete solo para `swift test`
```

## Qué se quitó

Se eliminó el backend simulado (`HospitalBackend`), los usuarios de prueba con contraseñas y el panel operativo de
administrador, recepcionista y asistente (habitaciones, laboratorio, ambulancia, consulta, turnos de administración),
porque dependían por completo de ese simulador y la API no tiene esas operaciones para iOS. Quedan en el historial de git.
Los módulos clínicos de Médico y Paciente vuelven cuando la API los exponga.
