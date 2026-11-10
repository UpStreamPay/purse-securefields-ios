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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/sdk-v1.11.0/PurseSecureFields.xcframework.zip",
            checksum: "b753fa7787ccd1b9aa5ea614853ae45dcd49a331364bd65e395539c5c7121f29"
        )
    ]
)
