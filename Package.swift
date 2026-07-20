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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/v1.4.0/PurseSecureFields.xcframework.zip",
            checksum: "185429fbb6fb99eb7e379d35b2e0fd9f81d54df7352f963e619a5d69d5bc2ae9"
        )
    ]
)
