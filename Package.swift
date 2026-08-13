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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/v1.6.0/PurseSecureFields.xcframework.zip",
            checksum: "239af50e66d03da7d3e5fda7d5cbc9ae6e679ae02ba134717c4d3639fad504c3"
        )
    ]
)
