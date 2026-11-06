# Climesa iOS — Segunda Entrega

## 1. Objetivo

Documentar los avances de la aplicación iOS del Sistema de Gestión Hospitalaria, desarrollada con Swift y SwiftUI, conforme a los requisitos establecidos para la entrega final del proyecto.

La implementación debe mantener la consistencia visual de la aplicación original.

## 2. Funcionalidades incorporadas al código

### 2.1 Gestión de habitaciones

Se incorporaron reglas locales para:

- Reconocer las cinco habitaciones VIP, VIP-301 a VIP-305.
- Reconocer las seis habitaciones semiprivadas, HAB-201 a HAB-206, con dos camas cada una.
- Validar identificadores de camas.
- Rechazar asignaciones duplicadas.
- Consultar camas disponibles según el estado recibido.

**Limitación:** estas reglas locales no garantizan por sí solas que el backend impida asignaciones simultáneas.

### 2.2 Laboratorio

Se incorporó el modelo `LabProgress`, que contempla los estados:

- Pendiente.
- En Proceso.
- Completado.

Se definieron transiciones válidas entre estos estados.

**Limitación:** queda pendiente verificar la persistencia de las órdenes de laboratorio en el servidor.

### 2.3 Privacidad clínica

Se incorporaron reglas locales de acceso mediante `ClinicalPrivacyRules`.

La información médica privada debe limitarse a usuarios autorizados.

**Limitación:** la autorización efectiva debe aplicarse también en el backend.

### 2.4 Información pública

Se modificó la pantalla de información pública para consumir el contrato propuesto `GET /hospital/publico`.

La información contempla ocupación hospitalaria, médicos de turno y avisos generales.

**Limitación:** la disponibilidad del endpoint y la integración real deben comprobarse.

## 3. Cobertura de requisitos

| Requisito | Estado |
|---|---|
| Estructura del proyecto Swift/SwiftUI | Existente; requiere validación en Xcode |
| Reglas de habitaciones VIP y semiprivadas | Implementadas localmente |
| Prevención local de asignaciones duplicadas | Implementada |
| Prevención de sobrecupo en backend | Pendiente de integración y pruebas |
| Estados de laboratorio | Modelados |
| Registro y persistencia de laboratorio | Pendiente de verificación |
| Reglas locales de privacidad | Incorporadas |
| Protección de datos mediante autorización del servidor | Pendiente de verificación |
| Información pública desde API | Código incorporado; endpoint pendiente de verificación |
| Gestión integral de consulta general | Pendiente de validación |
| Ambulancia única y despacho en tiempo real | Pendiente de integración y validación |
| Integración con Android y Web | Pendiente |
| Pruebas completas en Xcode | Pendiente |

## 4. Pruebas requeridas

### Habitaciones

- Verificar que el catálogo incluya exactamente cinco habitaciones VIP.
- Verificar que existan doce camas semiprivadas.
- Rechazar una cama inexistente.
- Rechazar la asignación de una cama ocupada.
- Rechazar la asignación duplicada de un paciente.
- Comprobar dos solicitudes simultáneas sobre la misma cama en el backend.

### Laboratorio

- Validar la transición Pendiente → En Proceso.
- Validar la transición En Proceso → Completado.
- Rechazar transiciones no permitidas.
- Comprobar que los estados se guarden y recuperen desde el servidor.

### Privacidad

- Verificar el acceso autorizado al expediente clínico.
- Rechazar el acceso de usuarios sin permisos.
- Comprobar que la API pública no devuelva información clínica privada.

### Información pública

- Comprobar carga exitosa de datos.
- Comprobar los estados de error y reintento.
- Rechazar valores de ocupación fuera de los límites.
- Verificar el funcionamiento con el backend real.

## 5. Evidencia pendiente

Para la presentación final se deben incorporar:

- Capturas de las pantallas funcionales.
- Resultados de las pruebas ejecutadas en Xcode.
- Evidencias de las respuestas de la API.
- Pruebas de integración entre iOS, Android y Web.
- Registro de errores encontrados y corregidos.
- Evidencia del funcionamiento de habitaciones, laboratorio, consulta general y ambulancia.

## 6. Limitaciones

El código incorporado todavía requiere pruebas de compilación e integración mediante Xcode en macOS.

La documentación de contratos no confirma que los endpoints estén implementados.

Los requisitos que dependen del backend o de otras plataformas no pueden considerarse cumplidos únicamente mediante los cambios realizados en iOS.

## 7. Próximas actividades

1. Verificar la compilación del proyecto completo.
2. Ejecutar y registrar las pruebas unitarias.
3. Integrar los endpoints definitivos.
4. Validar autenticación, permisos y operaciones clínicas.
5. Realizar pruebas de concurrencia.
6. Verificar los flujos entre las tres plataformas.
7. Preparar la demostración final y la documentación de arquitectura.