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
            url: "https://github.com/UpStreamPay/vault-ios/releases/download/v1.0.4/PurseSecureFields.xcframework.zip",
            checksum: "ae8c3b48936a739f93a957fdf8fe84cbcc0dc29b1d30df605b97d4ada2d7d1ac"
        )
    ]
)
