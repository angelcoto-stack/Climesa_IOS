import XCTest
import Foundation
@testable import ClimesaCore

/// Reglas puras de ambulancia, turnos y personal (datos ficticios, sin red ni UI).
final class OperationsRulesTests: XCTestCase {
    // MARK: - Ayudas

    private func perm(_ code: String) -> Permission { Permission(code: code, context: "propio") }

    private func profile(_ codes: [String], roles: [String] = ["MED"], platforms: [String] = ["ios"]) -> AccessProfile {
        let permissions = (["sesion.perfil"] + codes).map { perm($0) }
        return AccessProfile(id: "u1", email: "ejemplo@example.test", name: "Cuenta ficticia", roles: roles,
                             platforms: platforms, permissions: permissions)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func date(_ text: String) throws -> Date {
        return try XCTUnwrap(OperationsDates.parse(text))
    }

    private func status(_ state: String, paramedic: Bool? = true, version: Int = 3) -> AmbulanceStatus {
        return AmbulanceStatus(unit: AmbulanceUnit(id: "u", plate: "AMB-01", state: state, version: version),
                               activeService: nil, paramedicOnDuty: paramedic)
    }

    private func shift(state: String = "borrador", staffId: String? = "s1", areaId: String? = "a1", type: String? = "diurno",
                       version: Int? = 2, start: String = "2026-11-10T14:00:00Z", end: String = "2026-11-10T22:00:00Z") -> PlannedShift {
        return PlannedShift(id: "t1", staffId: staffId, person: "Ana Pérez", areaId: areaId, area: "Emergencia",
                            start: start, end: end, type: type, state: state, version: version)
    }

    // MARK: - Etiquetas

    func testFuncionMedicoSeMuestraEnEspanol() {
        XCTAssertEqual(StaffLabels.function("medico"), "Médico")
        XCTAssertEqual(StaffLabels.function("enfermero"), "Enfermería")
        XCTAssertEqual(StaffLabels.function("paramedico"), "Paramédico")
    }

    func testCodigoDesconocidoSeMuestraTalCual() {
        XCTAssertEqual(StaffLabels.function("nuevo_cargo"), "nuevo_cargo")
        XCTAssertEqual(StaffLabels.shiftState("raro"), "raro")
    }

    func testEtiquetasDeTurnoYUnidad() {
        XCTAssertEqual(StaffLabels.shiftState("en_curso"), "En curso")
        XCTAssertEqual(StaffLabels.shiftType("guardia"), "Guardia médica")
        XCTAssertEqual(StaffLabels.unitState("en_mantenimiento"), "En mantenimiento")
        XCTAssertEqual(StaffLabels.coverageRole("medico"), "Medicina")
    }

    // MARK: - Secciones por permiso (TabPolicy)

    func testSinPermisosNoHaySecciones() {
        XCTAssertEqual(TabPolicy.sections(for: profile([])), [])
    }

    func testCadaSeccionAparecePorSuPermiso() {
        XCTAssertEqual(TabPolicy.sections(for: profile(["ambulancia.ver_estado"])), [.ambulancia])
        XCTAssertEqual(TabPolicy.sections(for: profile(["turnos.ver"])), [.planificacion])
        XCTAssertEqual(TabPolicy.sections(for: profile(["personal.ver"])), [.personal])
    }

    func testSeccionesEnElOrdenDeLaPantalla() {
        let all = profile(["personal.ver", "turnos.ver", "ambulancia.ver_estado"])
        XCTAssertEqual(TabPolicy.sections(for: all), [.ambulancia, .planificacion, .personal])
    }

    func testPermisosDeAccionNoAbrenSeccionesDeLectura() {
        let onlyActions = profile(["ambulancia.mantenimiento", "turnos.planificar", "turnos.publicar", "personal.gestionar"])
        XCTAssertEqual(TabPolicy.sections(for: onlyActions), [])
    }

    func testSinAccesoAIosNoHaySecciones() {
        let web = profile(["ambulancia.ver_estado", "turnos.ver", "personal.ver"], platforms: ["web"])
        XCTAssertEqual(TabPolicy.sections(for: web), [])
    }

    func testCadaSeccionCoincideConElCatalogo() {
        XCTAssertEqual(ManagementSection.ambulancia.requiredPermission, "ambulancia.ver_estado")
        XCTAssertEqual(ManagementSection.planificacion.requiredPermission, "turnos.ver")
        XCTAssertEqual(ManagementSection.personal.requiredPermission, "personal.ver")
    }

    // MARK: - Motivo

    func testMotivoDeNueveCaracteresEsCorto() {
        XCTAssertEqual(ReasonRules.error("123456789"), "Indica el motivo, de al menos 10 caracteres.")
    }

    func testMotivoDeDiezCaracteresEsValido() {
        XCTAssertNil(ReasonRules.error("1234567890"))
    }

    func testMotivoSeValidaSinEspaciosSobrantes() {
        XCTAssertNotNil(ReasonRules.error("   corto    "))
    }

    func testMotivoDe500EsValidoYDe501No() {
        XCTAssertNil(ReasonRules.error(String(repeating: "a", count: 500)))
        XCTAssertEqual(ReasonRules.error(String(repeating: "a", count: 501)), "El motivo no puede pasar de 500 caracteres.")
    }

    func testClampRecortaA500() {
        XCTAssertEqual(ReasonRules.clamp(String(repeating: "a", count: 600)).count, 500)
        XCTAssertEqual(ReasonRules.clamp("hola"), "hola")
    }

    // MARK: - Mantenimiento

    func testMantenimientoDisponibleConPermisoYSinServicio() {
        let manager = profile(["ambulancia.mantenimiento"])
        XCTAssertTrue(MaintenanceRules.available(profile: manager, unitState: "disponible"))
        XCTAssertTrue(MaintenanceRules.available(profile: manager, unitState: "en_mantenimiento"))
        XCTAssertFalse(MaintenanceRules.available(profile: manager, unitState: "en_servicio"))
    }

    func testMantenimientoNoSeOfreceSinPermiso() {
        XCTAssertFalse(MaintenanceRules.available(profile: profile(["ambulancia.ver_estado"]), unitState: "disponible"))
    }

    func testSalirDeMantenimientoExigeParamedicoConTurno() {
        XCTAssertTrue(MaintenanceRules.leavingBlocked(unitState: "en_mantenimiento", paramedicOnDuty: false))
        XCTAssertFalse(MaintenanceRules.leavingBlocked(unitState: "en_mantenimiento", paramedicOnDuty: true))
        XCTAssertFalse(MaintenanceRules.leavingBlocked(unitState: "disponible", paramedicOnDuty: false))
    }

    func testPrepararEntradaAMantenimientoArmaElCuerpo() throws {
        let result = MaintenanceRules.prepare(status: status("disponible", version: 4),
                                              profile: profile(["ambulancia.mantenimiento"]),
                                              reason: "  Cambio de aceite programado  ")
        let request = try result.get()
        XCTAssertEqual(request.version, 4)
        XCTAssertTrue(request.inMaintenance)
        XCTAssertEqual(request.reason, "Cambio de aceite programado")
        XCTAssertEqual(try encoded(request), "{\"inMaintenance\":true,\"reason\":\"Cambio de aceite programado\",\"version\":4}")
    }

    func testPrepararSalidaDeMantenimientoEnviaFalso() throws {
        let result = MaintenanceRules.prepare(status: status("en_mantenimiento", paramedic: true),
                                              profile: profile(["ambulancia.mantenimiento"]),
                                              reason: "Revision terminada")
        XCTAssertFalse(try result.get().inMaintenance)
    }

    func testPrepararRechazaMotivoCorto() {
        let result = MaintenanceRules.prepare(status: status("disponible"), profile: profile(["ambulancia.mantenimiento"]), reason: "corto")
        XCTAssertEqual(result, .failure(ValidationError("Indica el motivo, de al menos 10 caracteres.")))
    }

    func testPrepararRechazaServicioActivo() {
        let result = MaintenanceRules.prepare(status: status("en_servicio"), profile: profile(["ambulancia.mantenimiento"]),
                                              reason: "Motivo suficientemente largo")
        XCTAssertEqual(result, .failure(ValidationError("No puedes cambiar el mantenimiento de la unidad en este momento.")))
    }

    func testPrepararRechazaSalirSinParamedico() {
        let result = MaintenanceRules.prepare(status: status("en_mantenimiento", paramedic: nil),
                                              profile: profile(["ambulancia.mantenimiento"]),
                                              reason: "Motivo suficientemente largo")
        XCTAssertEqual(result, .failure(ValidationError(MaintenanceRules.blockedMessage)))
    }

    func testPrepararRechazaSinPermiso() {
        let result = MaintenanceRules.prepare(status: status("disponible"), profile: profile([]), reason: "Motivo suficientemente largo")
        XCTAssertEqual(result, .failure(ValidationError("No puedes cambiar el mantenimiento de la unidad en este momento.")))
    }

    // MARK: - Estado de la ambulancia (decodificación)

    func testDecodificaElEstadoConServicioActivo() throws {
        let json = """
        {"unit":{"id":"u1","plate":"AMB-01","state":"en_servicio","version":7},
         "activeService":{"id":"s1","type":"emergencia_domicilio","priority":"roja","origin":"Colonia Escalón","destination":"Hospital Climesa",
                          "dispatchedAt":"2026-11-10T14:00:00Z","crew":[{"staffId":"p1","role":"paramedico","name":"Ana Pérez"}]},
         "paramedicOnDuty":true}
        """
        let value = try decode(AmbulanceStatus.self, json)
        XCTAssertEqual(value.unit.version, 7)
        XCTAssertEqual(value.activeService?.crew?.first?.name, "Ana Pérez")
        XCTAssertTrue(value.hasParamedicOnDuty)
    }

    func testDecodificaElEstadoSinServicioNiParamedico() throws {
        let value = try decode(AmbulanceStatus.self, "{\"unit\":{\"id\":\"u1\",\"plate\":\"AMB-01\",\"state\":\"disponible\",\"version\":1},\"activeService\":null}")
        XCTAssertNil(value.activeService)
        XCTAssertFalse(value.hasParamedicOnDuty)
    }

    // MARK: - Turnos

    func testDecodificaUnTurno() throws {
        let json = "{\"id\":\"t1\",\"staffId\":\"s1\",\"person\":\"Ana Pérez\",\"areaId\":\"a1\",\"area\":\"Emergencia\",\"start\":\"2026-11-10T14:00:00Z\",\"end\":\"2026-11-10T22:00:00Z\",\"type\":\"diurno\",\"state\":\"publicado\",\"version\":2}"
        let value = try decode(PlannedShift.self, json)
        XCTAssertEqual(value.person, "Ana Pérez")
        XCTAssertEqual(value.version, 2)
    }

    func testUnTurnoIncompletoNoTumbaLaLista() throws {
        let rows = try decode([PlannedShift].self, "[{\"id\":\"t1\",\"start\":\"2026-11-10T14:00:00Z\",\"end\":\"2026-11-10T22:00:00Z\",\"state\":\"publicado\"}]")
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].version)
    }

    func testPuedeCancelarConPermisoEstadoYDatosCompletos() {
        let planner = profile(["turnos.ver", "turnos.planificar"])
        XCTAssertTrue(ShiftRules.canCancel(shift(state: "borrador"), profile: planner))
        XCTAssertTrue(ShiftRules.canCancel(shift(state: "publicado"), profile: planner))
        XCTAssertFalse(ShiftRules.canCancel(shift(state: "cancelado"), profile: planner))
        XCTAssertFalse(ShiftRules.canCancel(shift(state: "completado"), profile: planner))
        XCTAssertFalse(ShiftRules.canCancel(shift(state: "en_curso"), profile: planner))
    }

    func testNoPuedeCancelarSinPermisoDePlanificar() {
        XCTAssertFalse(ShiftRules.canCancel(shift(), profile: profile(["turnos.ver", "turnos.publicar"])))
    }

    func testNoPuedeCancelarSiFaltanDatosDelTurno() {
        let planner = profile(["turnos.planificar"])
        XCTAssertFalse(ShiftRules.canCancel(shift(staffId: nil), profile: planner))
        XCTAssertFalse(ShiftRules.canCancel(shift(areaId: nil), profile: planner))
        XCTAssertFalse(ShiftRules.canCancel(shift(type: nil), profile: planner))
        XCTAssertFalse(ShiftRules.canCancel(shift(version: nil), profile: planner))
    }

    func testCancelarArmaElCuerpoConEstadoVersionYMotivo() throws {
        let request = try ShiftRules.prepareCancel(shift(), profile: profile(["turnos.planificar"]), reason: " Ausencia justificada ").get()
        XCTAssertEqual(request.state, "cancelado")
        XCTAssertEqual(request.version, 2)
        XCTAssertEqual(request.reason, "Ausencia justificada")
        let expected = "{\"areaId\":\"a1\",\"end\":\"2026-11-10T22:00:00Z\",\"reason\":\"Ausencia justificada\",\"staffId\":\"s1\",\"start\":\"2026-11-10T14:00:00Z\",\"state\":\"cancelado\",\"type\":\"diurno\",\"version\":2}"
        XCTAssertEqual(try encoded(request), expected)
    }

    func testCancelarExigeMotivoDeDiezCaracteres() {
        let result = ShiftRules.prepareCancel(shift(), profile: profile(["turnos.planificar"]), reason: "poco")
        XCTAssertEqual(result, .failure(ValidationError("Indica el motivo de la cancelación, de al menos 10 caracteres.")))
    }

    func testCancelarSinPermisoSeRechaza() {
        let result = ShiftRules.prepareCancel(shift(), profile: profile(["turnos.ver"]), reason: "Motivo suficientemente largo")
        XCTAssertEqual(result, .failure(ValidationError("Este turno no se puede cancelar.")))
    }

    func testFiltroPorEstado() {
        let rows = [shift(state: "borrador"), shift(state: "publicado"), shift(state: "cancelado")]
        XCTAssertEqual(ShiftFilter.todos.apply(rows).count, 3)
        XCTAssertEqual(ShiftFilter.publicado.apply(rows).map { $0.state }, ["publicado"])
        XCTAssertEqual(ShiftFilter.enCurso.apply(rows), [])
        XCTAssertEqual(ShiftFilter.enCurso.rawValue, "en_curso")
    }

    func testAreasDeLosTurnosSinRepetirYOrdenadas() {
        let rows = [
            PlannedShift(id: "1", staffId: nil, person: nil, areaId: "b", area: "Urgencias", start: "x", end: "y", type: nil, state: "borrador", version: nil),
            PlannedShift(id: "2", staffId: nil, person: nil, areaId: "a", area: "Consulta", start: "x", end: "y", type: nil, state: "borrador", version: nil),
            PlannedShift(id: "3", staffId: nil, person: nil, areaId: "b", area: "Urgencias", start: "x", end: "y", type: nil, state: "borrador", version: nil),
            PlannedShift(id: "4", staffId: nil, person: nil, areaId: nil, area: "Sin id", start: "x", end: "y", type: nil, state: "borrador", version: nil)
        ]
        XCTAssertEqual(ShiftRules.areaOptions(rows), [AreaOption(id: "a", name: "Consulta"), AreaOption(id: "b", name: "Urgencias")])
    }

    func testProximosTurnosDeUnaPersona() throws {
        let now = try date("2026-11-10T12:00:00Z")
        let rows = [
            PlannedShift(id: "pasado", staffId: "s1", person: nil, areaId: nil, area: nil, start: "2026-11-09T14:00:00Z", end: "2026-11-09T22:00:00Z", type: nil, state: "publicado", version: 1),
            PlannedShift(id: "lejano", staffId: "s1", person: nil, areaId: nil, area: nil, start: "2026-11-20T14:00:00Z", end: "2026-11-20T22:00:00Z", type: nil, state: "publicado", version: 1),
            PlannedShift(id: "cercano", staffId: "s1", person: nil, areaId: nil, area: nil, start: "2026-11-11T14:00:00Z", end: "2026-11-11T22:00:00Z", type: nil, state: "borrador", version: 1),
            PlannedShift(id: "cancelado", staffId: "s1", person: nil, areaId: nil, area: nil, start: "2026-11-12T14:00:00Z", end: "2026-11-12T22:00:00Z", type: nil, state: "cancelado", version: 1),
            PlannedShift(id: "otra", staffId: "s2", person: nil, areaId: nil, area: nil, start: "2026-11-11T14:00:00Z", end: "2026-11-11T22:00:00Z", type: nil, state: "publicado", version: 1)
        ]
        XCTAssertEqual(ShiftRules.upcoming(rows, staffId: "s1", now: now).map { $0.id }, ["cercano", "lejano"])
    }

    func testProximosTurnosRespetanElLimite() throws {
        let now = try date("2026-11-10T12:00:00Z")
        let rows = (11...19).map { day in
            PlannedShift(id: "t\(day)", staffId: "s1", person: nil, areaId: nil, area: nil, start: "2026-11-\(day)T14:00:00Z", end: "2026-11-\(day)T22:00:00Z", type: nil, state: "publicado", version: 1)
        }
        XCTAssertEqual(ShiftRules.upcoming(rows, staffId: "s1", now: now, limit: 3).count, 3)
    }

    // MARK: - Publicar

    func testRangoValido() {
        XCTAssertNil(PublishRules.rangeError(from: "2026-11-10", to: "2026-11-16"))
        XCTAssertNil(PublishRules.rangeError(from: "2026-11-10", to: "2026-11-10"))
    }

    func testRangoConFinAnteriorSeRechaza() {
        XCTAssertEqual(PublishRules.rangeError(from: "2026-11-16", to: "2026-11-10"),
                       "Indica el inicio y el fin del rango; el fin no puede ser anterior al inicio.")
    }

    func testRangoConFechaInexistenteSeRechaza() {
        XCTAssertNotNil(PublishRules.rangeError(from: "2026-02-30", to: "2026-03-05"))
        XCTAssertNotNil(PublishRules.rangeError(from: "", to: "2026-03-05"))
        XCTAssertNotNil(PublishRules.rangeError(from: "10/11/2026", to: "2026-11-16"))
    }

    func testRangoMayorDe31DiasSeRechaza() {
        XCTAssertNil(PublishRules.rangeError(from: "2026-11-01", to: "2026-12-02"))
        XCTAssertEqual(PublishRules.rangeError(from: "2026-11-01", to: "2026-12-03"), "El rango no puede pasar de 31 días.")
    }

    func testDiaComoTextoConElCalendarioIndicado() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(PublishRules.dayString(try date("2026-11-05T12:00:00Z"), calendar: calendar), "2026-11-05")
        XCTAssertEqual(PublishRules.dayString(try date("2026-01-09T12:00:00Z"), calendar: calendar), "2026-01-09")
    }

    func testPublicarExigePermiso() {
        let result = PublishRules.prepare(from: "2026-11-10", to: "2026-11-16", areaId: nil, profile: profile(["turnos.ver", "turnos.planificar"]))
        XCTAssertEqual(result, .failure(ValidationError("No tienes permiso para publicar turnos.")))
    }

    func testPublicarSinAreaOmiteAreaId() throws {
        let request = try PublishRules.prepare(from: "2026-11-10", to: "2026-11-16", areaId: "", profile: profile(["turnos.publicar"])).get()
        XCTAssertNil(request.areaId)
        XCTAssertEqual(try encoded(request), "{\"from\":\"2026-11-10\",\"to\":\"2026-11-16\"}")
    }

    func testPublicarConAreaLaEnvia() throws {
        let request = try PublishRules.prepare(from: "2026-11-10", to: "2026-11-16", areaId: "a1", profile: profile(["turnos.publicar"])).get()
        XCTAssertEqual(try encoded(request), "{\"areaId\":\"a1\",\"from\":\"2026-11-10\",\"to\":\"2026-11-16\"}")
    }

    func testPublicarConRangoInvalidoDevuelveElMensaje() {
        let result = PublishRules.prepare(from: "2026-11-16", to: "2026-11-10", areaId: nil, profile: profile(["turnos.publicar"]))
        XCTAssertEqual(result, .failure(ValidationError("Indica el inicio y el fin del rango; el fin no puede ser anterior al inicio.")))
    }

    func testResultadoDePublicacionConHuecos() throws {
        let json = """
        {"from":"2026-11-10","to":"2026-11-16","published":12,"publishedBy":"u1","publishedAt":"2026-11-09T10:00:00Z",
         "warnings":[{"areaId":"a1","area":"Urgencias","role":"medico","start":"2026-11-10T14:00:00Z","end":"2026-11-10T22:00:00Z","required":2,"actual":1}]}
        """
        let result = try decode(PublishResult.self, json)
        XCTAssertEqual(result.published, 12)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(PublishRules.summary(result), "Se publicaron 12 turnos del 10/11/2026 al 16/11/2026. Hay 1 hueco de cobertura.")
        XCTAssertEqual(PublishRules.gapText(result.warnings[0]),
                       "Urgencias · Medicina · 10/11/2026 08:00 a 10/11/2026 16:00: faltan 1 (mínimo 2, programadas 1)")
    }

    func testResultadoSinTurnosEnBorrador() throws {
        let result = try decode(PublishResult.self, "{\"from\":\"2026-11-10\",\"to\":\"2026-11-16\",\"published\":0,\"warnings\":[]}")
        XCTAssertEqual(PublishRules.summary(result), "No había turnos en borrador en ese rango.")
    }

    func testResultadoSinAdvertenciasNiRango() throws {
        let result = try decode(PublishResult.self, "{\"published\":1}")
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(PublishRules.summary(result), "Se publicó 1 turno.")
    }

    func testResultadoConVariosHuecos() {
        let gap = CoverageGap(areaId: nil, area: nil, role: nil, start: nil, end: nil, required: nil, actual: nil)
        let result = PublishResult(from: nil, to: nil, published: 3, warnings: [gap, gap])
        XCTAssertEqual(PublishRules.summary(result), "Se publicaron 3 turnos. Hay 2 huecos de cobertura.")
        XCTAssertEqual(PublishRules.gapText(gap), "Área sin nombre · Sin función · No disponible a No disponible: faltan 0 (mínimo 0, programadas 0)")
    }

    // MARK: - Personal

    private var directory: [StaffMember] {
        return [
            StaffMember(id: "1", givenNames: "Ana", surnames: "Pérez", type: "medico", specialty: "Cardiología", area: "Consulta", active: true),
            StaffMember(id: "2", givenNames: "Luis", surnames: "Gómez", type: "enfermero", specialty: nil, area: nil, active: false),
            StaffMember(id: "3", givenNames: "María", surnames: "López", type: "paramedico", specialty: "Emergencias", area: "Urgencias", active: nil)
        ]
    }

    func testDirectorioPorEstado() {
        XCTAssertEqual(StaffDirectory.filter(directory, query: "", scope: .activos).map { $0.id }, ["1", "3"])
        XCTAssertEqual(StaffDirectory.filter(directory, query: "", scope: .inactivos).map { $0.id }, ["2"])
        XCTAssertEqual(StaffDirectory.filter(directory, query: "", scope: .todos).count, 3)
    }

    func testDirectorioBuscaSinTildesNiMayusculas() {
        XCTAssertEqual(StaffDirectory.filter(directory, query: "perez", scope: .todos).map { $0.id }, ["1"])
        XCTAssertEqual(StaffDirectory.filter(directory, query: "MARIA", scope: .todos).map { $0.id }, ["3"])
        XCTAssertEqual(StaffDirectory.filter(directory, query: "cardiologia", scope: .todos).map { $0.id }, ["1"])
        XCTAssertEqual(StaffDirectory.filter(directory, query: "  ", scope: .todos).count, 3)
        XCTAssertEqual(StaffDirectory.filter(directory, query: "inexistente", scope: .todos), [])
    }

    func testPersonalDecodificaInscripcionesYNoLeeDatosPersonales() throws {
        let json = """
        {"id":"p1","givenNames":"Ana","surnames":"Pérez","type":"medico","specialty":"Cardiología","area":"Consulta","active":true,"version":2,
         "phone":"7000-0000","dui":"00000000-0",
         "registrations":[{"id":"r1","board":"JVPM","number":"1234","validFrom":"2025-01-01","validTo":"2027-01-01"}]}
        """
        let person = try decode(StaffMember.self, json)
        XCTAssertEqual(person.fullName, "Ana Pérez")
        XCTAssertEqual(StaffLabels.function(person.type), "Médico")
        XCTAssertEqual(person.registrations?.count, 1)
        XCTAssertEqual(StaffDirectory.vigency(try XCTUnwrap(person.registrations?.first)), "01/01/2025 al 01/01/2027")
    }

    func testPersonalSinActivoSeConsideraActivo() throws {
        let person = try decode(StaffMember.self, "{\"id\":\"p1\",\"givenNames\":\"Ana\",\"surnames\":\"Pérez\",\"type\":\"otro\"}")
        XCTAssertTrue(person.isActive)
    }

    // MARK: - Fechas

    func testFechaSeMuestraEnHoraDeElSalvador() {
        XCTAssertEqual(OperationsDates.text("2026-11-10T14:00:00Z"), "10/11/2026 08:00")
        XCTAssertEqual(OperationsDates.text("2026-11-10T03:30:00.250Z"), "09/11/2026 21:30")
    }

    func testFechaInvalidaONulaNoDisponible() {
        XCTAssertEqual(OperationsDates.text(nil), "No disponible")
        XCTAssertEqual(OperationsDates.text("ayer"), "No disponible")
    }

    func testDiaSeMuestraConBarras() {
        XCTAssertEqual(OperationsDates.dayText("2026-11-10"), "10/11/2026")
        XCTAssertEqual(OperationsDates.dayText("otra cosa"), "otra cosa")
    }
}
