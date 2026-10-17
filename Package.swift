// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AntigravityQuota",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AntigravityQuota", targets: ["AntigravityQuota"])
    ],
    targets: [
        .executableTarget(
            name: "AntigravityQuota",
            path: "Sources/AntigravityQuota"
        )
    ]
)
