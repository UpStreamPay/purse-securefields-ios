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
            url: "https://github.com/UpStreamPay/vault-ios/releases/download/v1.1.6/PurseSecureFields.xcframework.zip",
            checksum: "b52f94b4a123d5455c4579f3ec466bcd823c6482adbd7fdb7826f7fea9679f86"
        )
    ]
)
