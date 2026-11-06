# Contratos de Backend — Climesa iOS

## 1. Objetivo

Documentar los contratos de API propuestos para la segunda entrega del Sistema de Gestión Hospitalaria, incluyendo información pública, ocupación de habitaciones, asignación de camas, privacidad y concurrencia.

**Estado:** Contratos propuestos. Su implementación y disponibilidad en el backend deben verificarse.

## 2. Información pública del hospital

**Endpoint propuesto:** `GET /hospital/publico`

Información que debe proporcionar:

- Número de habitaciones VIP ocupadas, entre 0 y 5.
- Número de camas semiprivadas ocupadas, entre 0 y 12.
- Médicos de turno y especialidades.
- Avisos generales del hospital.

Los datos públicos no deben incluir nombres de pacientes, diagnósticos, expedientes ni asignaciones individuales de habitaciones.

## 3. Asignación de habitaciones

**Operación requerida:** asignar una cama disponible a un paciente autorizado.

Reglas de negocio:

- Planta 3: cinco habitaciones VIP, de VIP-301 a VIP-305.
- Planta 2: seis habitaciones semiprivadas, de HAB-201 a HAB-206, con dos camas por habitación.
- Un paciente no puede tener dos asignaciones activas.
- Una cama no puede estar asignada simultáneamente a dos pacientes.
- La operación debe ejecutarse de forma atómica en el backend.

El servidor debe rechazar las asignaciones que incumplan estas reglas.

## 4. Control de concurrencia

Cuando dos usuarios intenten asignar simultáneamente la misma cama, solamente una operación debe completarse.

El backend debe garantizar esta condición mediante transacciones y restricciones de integridad. Las validaciones locales de Swift no sustituyen las del servidor.

## 5. Privacidad y permisos

Los expedientes, diagnósticos y resultados de laboratorio son información protegida.

El backend debe verificar la identidad y autorización del solicitante en cada operación.

No se debe confiar únicamente en la ocultación de vistas de la aplicación móvil.

## 6. Integración y validación

Antes de considerar completada la integración, deberán comprobarse:

- Respuestas reales del servidor.
- Manejo de errores HTTP y conexiones fallidas.
- Rechazo de operaciones no autorizadas.
- Ausencia de sobreocupación o asignaciones duplicadas.
- Consistencia de datos entre iOS, Android y Web.
- Ausencia de datos clínicos privados en respuestas públicas.

## 7. Estado de implementación

Este documento define requisitos y contratos de integración. No confirma que los endpoints estén desarrollados o desplegados.

Los endpoints definitivos, esquemas de respuesta y mecanismos de autenticación deberán acordarse con el equipo responsable del backend.