import XCTest
import Foundation
@testable import ClimesaCore

/// Reglas del formulario de registro: nombre, correo, contraseña y confirmación (datos ficticios).
final class RegistrationRulesTests: XCTestCase {
    private let goodName = "Cuenta Ejemplo"
    private let goodEmail = "ejemplo@example.test"
    private let goodPassword = "Segura#2026"

    private func errors(name: String? = nil, email: String? = nil, password: String? = nil, confirmation: String? = nil) -> [String] {
        let usedPassword: String = password ?? goodPassword
        return RegistrationRules.errors(
            name: name ?? goodName,
            email: email ?? goodEmail,
            password: usedPassword,
            confirmation: confirmation ?? usedPassword
        )
    }

    func testUnFormularioCorrectoNoTieneErrores() {
        XCTAssertTrue(errors().isEmpty)
    }

    func testElNombreAceptaDeDosACientoVeinteCaracteres() {
        XCTAssertTrue(errors(name: "Al").isEmpty)
        XCTAssertEqual(errors(name: "A").count, 1)
        XCTAssertTrue(errors(name: String(repeating: "a", count: 120)).isEmpty)
        XCTAssertEqual(errors(name: String(repeating: "a", count: 121)).count, 1)
    }

    func testElNombreSeMideSinEspaciosAlInicioNiAlFinal() {
        XCTAssertEqual(errors(name: "   ").count, 1)
        XCTAssertEqual(errors(name: " A ").count, 1)
        XCTAssertTrue(errors(name: " Al ").isEmpty)
        XCTAssertEqual(errors(name: "").count, 1)
    }

    func testElCorreoExigeArrobaYDominioConPunto() {
        XCTAssertTrue(errors(email: "a@b.c").isEmpty)
        XCTAssertEqual(errors(email: "a@b").count, 1)
        XCTAssertEqual(errors(email: "ab.example.test").count, 1)
        XCTAssertEqual(errors(email: "@example.test").count, 1)
        XCTAssertEqual(errors(email: "a b@example.test").count, 1)
        XCTAssertEqual(errors(email: "a@@example.test").count, 1)
        XCTAssertEqual(errors(email: "").count, 1)
    }

    func testLaContrasenaDebeTenerAlMenosOchoCaracteres() {
        XCTAssertTrue(errors(password: "Abcdef1!").isEmpty, "ocho caracteres es el mínimo")
        XCTAssertEqual(errors(password: "Abcde1!").count, 1, "siete caracteres no alcanza")
    }

    func testLaContrasenaExigeMayusculaMinusculaNumeroYSimbolo() {
        XCTAssertEqual(errors(password: "abcdefg1!").count, 1, "sin mayúscula")
        XCTAssertEqual(errors(password: "ABCDEFG1!").count, 1, "sin minúscula")
        XCTAssertEqual(errors(password: "Abcdefgh!").count, 1, "sin número")
        XCTAssertEqual(errors(password: "Abcdefg12").count, 1, "sin símbolo")
        XCTAssertEqual(errors(password: "").count, 1)
    }

    func testLaConfirmacionDebeSerIgualALaContrasena() {
        XCTAssertEqual(errors(confirmation: "Segura#2027").count, 1)
        XCTAssertEqual(errors(confirmation: "").count, 1)
        XCTAssertEqual(errors(confirmation: "segura#2026").count, 1, "distingue mayúsculas")
    }

    func testSeAcumulanLosErroresDeTodosLosCampos() {
        let all: [String] = RegistrationRules.errors(name: "", email: "no", password: "abc", confirmation: "xyz")
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(Set(all).count, 4, "cada regla tiene su propio mensaje")
    }
}
