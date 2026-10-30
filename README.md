# Climesa · Hospital universitario (iOS, SwiftUI)

App iOS nativa (Swift / SwiftUI, iOS 16+, Xcode 15+) del proyecto integrador. Arquitectura **MVVM** con `async/await`.
El flujo de acceso replica las 8 pantallas del diseño Figma "iOS / Acceso".

## Cómo ejecutar

1. Descomprime el zip y haz doble clic en **`Climesa.xcodeproj`** (Xcode 15 o superior; no hay que instalar nada más).
2. Arriba en Xcode elige un simulador (p. ej. *iPhone 15*).
3. Si Xcode lo pide: Signing & Capabilities → Team → tu Apple ID (para el simulador basta).
4. Pulsa **▶ (Cmd+R)**.

`project.yml` es opcional (solo si quieres regenerar el proyecto con XcodeGen al añadir archivos; si no, arrastra los nuevos `.swift` al grupo `Climesa` en Xcode).

No requiere variables de entorno: el backend es local (`HospitalBackend`, un `actor` persistido en `UserDefaults`).
Para probar el error de conexión: Scheme → Run → Arguments → `-simulateOffline`.

## Mapa del diseño → estados

| Pantalla Figma | Dónde |
|---|---|
| Ingreso / Error de ingreso / Confirmación / Validando credenciales | `LoginView` (`errorMessage`, `infoMessage`, `isLoading`) |
| Registro de paciente / Error de registro | `RegisterView` |
| Comprobando | `CheckingView` (restaura la sesión al abrir) |
| Verificación (sin conexión) | `ConnectionErrorView` |

## Vistas Medicina y Paciente (shell con barra inferior)

Doctores y pacientes entran al shell claro del diseño nuevo (`Climesa/Shell/ShellViews.swift`):
Medicina = Inicio · Consultas · Mis turnos · Mi cuenta; Paciente = Inicio · Citas · Resultados · Mi cuenta.
Mis turnos tiene sus 4 estados (consultando, con datos, vacío, error). Consultas / Citas / Resultados muestran
"Este módulo todavía no está habilitado" (próxima entrega); `FeatureFlags.clinicalModulesEnabled = true` activa los módulos ya construidos.
Administrador, recepcionista y asistente (sin diseño en Figma) conservan el panel operativo anterior.

| Pantalla Figma | Cuenta | Cómo verla |
|---|---|---|
| MED / Inicio, Consultas, Mi cuenta | med@example.test · Medico123! | pestañas |
| MED / Mis turnos (con datos) | med@example.test | pestaña Mis turnos |
| MED / Mis turnos (vacío) | medpac@example.test · Medico123! | pestaña Mis turnos |
| MED / Mis turnos (error) | cualquier MED | Mi cuenta → "Simular sin conexión" → Mis turnos |
| MED / Mis turnos (cargando) | cualquier MED | se ve ~1 s al entrar |
| MED + PAC / Mi cuenta (selector) | medpac@example.test | Mi cuenta → Medicina / Paciente |
| PAC / Inicio, Citas, Resultados, Mi cuenta | pac@example.test · Paciente123! | pestañas |

## Usuarios de prueba

| Rol | Correo | Contraseña |
|---|---|---|
| Administrador | admin@climesa.com | Admin123! |
| Doctor | doctor@climesa.com | Doctor123! |
| Recepcionista | recepcion@climesa.com | Recep123! |
| Asistente | asistente@climesa.com | Asist123! |
| Paciente | paciente@climesa.com | Paciente123! |

Pacientes adicionales: marta@, luis@, carla@climesa.com (misma clave de paciente). Registrarse crea siempre un **paciente**.
En demo las cuentas nuevas se activan solas (`HospitalBackend.autoActivateAccounts`); ponlo en `false` para ver el error "cuenta todavía no está activa".

## Reglas de negocio implementadas

- 5 VIP (VIP-301…305, 3ª planta) + 6 semiprivadas de 2 camas (HAB-201…206, 2ª planta). **Sin sobrecupo ni doble asignación** (validado dentro del actor, después de cada `await`). Asignación manual y automática.
- Turnos con "médicos de turno ahora" calculado por hora actual (soporta turnos nocturnos).
- Laboratorio: Pendiente → En proceso → Completado (el resultado es obligatorio al completar).
- Ambulancia única: Disponible / En servicio / En mantenimiento, solicitud de paciente, despacho, bitácora filtrable y sondeo cada 3 s.
- Privacidad: público = ocupación, médicos de turno, avisos. Privado = expediente, laboratorio, habitación, datos personales.

## Matriz RBAC

| Acción | Admin | Doctor | Recep. | Asistente | Paciente |
|---|:-:|:-:|:-:|:-:|:-:|
| Info pública (inicio) | ✔ | ✔ | ✔ | ✔ | ✔ |
| Asignar / dar de alta camas | ✔ | – | ✔ | ✔ | – |
| Ver ocupantes de habitaciones | ✔ | solo sus pacientes | ✔ | ✔ | solo la propia |
| Crear consulta / orden de lab | – | ✔ | – | – | – |
| Ver consultas | todas | las suyas | – | – | las propias |
| Ver laboratorio | todos | los suyos | – | todos | los propios |
| Avanzar estado de lab | ✔ | las suyas | – | ✔ | – |
| Ver / editar turnos | ✔ / ✔ | ver | ver | ver | solo médicos |
| Solicitar ambulancia | ✔ | ✔ | ✔ | ✔ | solicitud |
| Despachar / finalizar | ✔ | ✔ | ✔ | ✔ | – |
| Mantenimiento ambulancia | ✔ | – | – | – | – |
| Bitácora ambulancia | ✔ | ✔ | ✔ | ✔ | – |

## Estructura
```
Climesa/
  App/ClimesaApp.swift      Core/Theme.swift        Models/Models.swift
  Services/HospitalBackend.swift
  Auth/AuthViewModel.swift  Auth/AuthViews.swift
  Features/ MainView · RoomsView · AmbulanceView · LabView · ConsultationView · ShiftsView
```

## Siguiente paso hacia el proyecto completo
Sustituir `HospitalBackend` por un cliente URLSession contra el backend compartido con Android y Web (misma superficie de métodos, mismo RBAC); el diseño de pantallas del dashboard, Android y Web no está cubierto por esta entrega.
