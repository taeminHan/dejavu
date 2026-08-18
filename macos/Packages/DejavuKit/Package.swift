// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DejavuKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DejavuDomain", targets: ["DejavuDomain"]),
        .library(name: "DejavuApplication", targets: ["DejavuApplication"]),
        .library(name: "DejavuProviders", targets: ["DejavuProviders"]),
        .library(name: "DejavuPersistence", targets: ["DejavuPersistence"]),
        .library(name: "DejavuWidgetShared", targets: ["DejavuWidgetShared"])
    ],
    targets: [
        .target(name: "DejavuDomain"),
        .target(
            name: "DejavuApplication",
            dependencies: ["DejavuDomain"]
        ),
        .target(
            name: "DejavuProviders",
            dependencies: ["DejavuDomain", "DejavuApplication"]
        ),
        .target(
            name: "DejavuPersistence",
            dependencies: ["DejavuDomain"]
        ),
        .target(
            name: "DejavuWidgetShared",
            dependencies: ["DejavuDomain"]
        ),
        .testTarget(
            name: "DejavuDomainTests",
            dependencies: ["DejavuDomain"]
        ),
        .testTarget(
            name: "DejavuApplicationTests",
            dependencies: ["DejavuApplication", "DejavuDomain"]
        ),
        .testTarget(
            name: "DejavuProviderTests",
            dependencies: ["DejavuProviders", "DejavuDomain"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "DejavuPersistenceTests",
            dependencies: ["DejavuPersistence", "DejavuDomain"]
        ),
        .testTarget(
            name: "DejavuWidgetSharedTests",
            dependencies: ["DejavuWidgetShared", "DejavuDomain"]
        )
    ],
    swiftLanguageModes: [.v6]
)
