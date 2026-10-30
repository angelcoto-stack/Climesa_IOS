// swift-tools-version: 5.9
import PackageDescription

// Paquete solo para probar la lógica pura (sin UI) con `swift test` en macOS/CI.
// La app compila esos mismos archivos directamente desde Climesa/Core/Logic.
let package = Package(
    name: "ClimesaCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ClimesaCore", targets: ["ClimesaCore"])],
    targets: [
        .target(name: "ClimesaCore", path: "Climesa/Core/Logic"),
        .testTarget(name: "CoreTests", dependencies: ["ClimesaCore"], path: "Tests/CoreTests")
    ]
)
