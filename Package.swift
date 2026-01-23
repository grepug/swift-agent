// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-agent",
    platforms: [
        .macOS(.v26),
        .iOS(.v17),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftAgent",
            targets: ["SwiftAgentCore"]
        ),
        .executable(
            name: "swift-agent-example",
            targets: ["Example"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/AnyLanguageModel.git", exact: "0.5.4")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftAgentCore",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel")
            ],
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "Example",
            dependencies: [
                "SwiftAgentCore",
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]
        ),
        .testTarget(
            name: "SwiftAgentCoreTests",
            dependencies: ["SwiftAgentCore"]
        ),
    ]
)
