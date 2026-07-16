// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PurseSecureFields",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PurseSecureFields", targets: ["PurseSecureFields"])
    ],
    targets: [
        .binaryTarget(
            name: "PurseSecureFields",
            url: "https://github.com/UpStreamPay/vault-ios/releases/download/v1.2.0/PurseSecureFields.xcframework.zip",
            checksum: "02be74cf7311f86f6e79b7b580a6b2d0630bb1b0639f55e1c667e3b71c3db967"
        )
    ]
)
