// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sKYCRASH",
    platforms: [.macOS(.v15)],
    targets: [
        // zlib du système (libz) : sauvegardes compressées et fichiers .gz
        .systemLibrary(name: "CZlib"),
        // Moteur d'audit, compatibilité, recoupements, export mORTEX, clients IA, veille : sans interface (testable seul)
        .target(name: "CrashCore", dependencies: ["CZlib"]),
        // Exécutable de comparaison avec la version Python : sort en JSON le résultat complet d'une analyse
        .executableTarget(name: "crash-parity", dependencies: ["CrashCore"]),
        .executableTarget(name: "sKYCRASH", dependencies: ["CrashCore"]),
        .testTarget(name: "CrashCoreTests", dependencies: ["CrashCore"], exclude: ["fixtures"]),
    ],
    swiftLanguageModes: [.v5]
)
