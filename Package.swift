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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/v1.7.0/PurseSecureFields.xcframework.zip",
            checksum: "4a1a3cc2d79776ec4687b673482c5be433de5de1db52ee7847d7f62227e5e072"
        )
    ]
)
