// swift-tools-version:5.9
// Live connectivity check against real XTCASH nodes (used by .github/workflows/live-node.yml).
import PackageDescription

let package = Package(
    name: "NodeCheck",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "XTEWalletCore", path: "../..")],
    targets: [
        .executableTarget(
            name: "xte-node-check",
            dependencies: [.product(name: "XTEWalletCore", package: "XTEWalletCore")]
        ),
    ]
)
