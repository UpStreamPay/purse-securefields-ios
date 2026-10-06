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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/sdk-v1.10.1/PurseSecureFields.xcframework.zip",
            checksum: "f77a11eb4c56347f89e3a9be4cc9b0bd61b3f5ec15f5dc4f3fa141252545fd34"
        )
    ]
)
