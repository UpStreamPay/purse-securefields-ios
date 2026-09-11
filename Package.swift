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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/v1.8.0/PurseSecureFields.xcframework.zip",
            checksum: "4b09db41f147a6529082f12277c8fbfa83bbad0778a2ec649ed0e17c3e0e7c99"
        )
    ]
)
