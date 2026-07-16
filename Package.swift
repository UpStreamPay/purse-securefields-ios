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
            url: "https://github.com/UpStreamPay/vault-ios/releases/download/v1.3.0/PurseSecureFields.xcframework.zip",
            checksum: "b2fcedf99a5937979c05527116a1b8e5e1991cef509c4b41b2e13309ae43b830"
        )
    ]
)
