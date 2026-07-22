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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/v1.5.0/PurseSecureFields.xcframework.zip",
            checksum: "5a258a828024e23a9eec9817f4d44b29af9fd087625ed473ec66cd064e32c4db"
        )
    ]
)
