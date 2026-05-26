// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetraNative",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Netra", targets: ["Netra"]),
    ],
    targets: [
        .executableTarget(
            name: "Netra",
            path: "Sources/Netra",
            resources: [
                .copy("Resources/master_oui.txt"),
                .copy("Resources/kismet_manuf.txt"),
                .copy("Resources/AppIcon.png"),
            ],
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("Network"),
            ]
        ),
    ]
)
