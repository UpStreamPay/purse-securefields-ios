// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PurseSecureFields",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "PurseSecureFields", type: .dynamic, targets: ["PurseSecureFields"])
    ],
    targets: [
        .target(name: "PurseSecureFields", resources: [.process("Resources")]),
        .testTarget(
            name: "PurseSecureFieldsTests",
            dependencies: ["PurseSecureFields"]
        )
    ]
)
