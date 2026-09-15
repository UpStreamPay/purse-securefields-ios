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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/v1.9.0/PurseSecureFields.xcframework.zip",
            checksum: "8755c4713705b608a1734b80bde0b53793bc1f7780d08a67a47f02aaf453c623"
        )
    ]
)
