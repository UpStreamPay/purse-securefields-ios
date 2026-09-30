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
            url: "https://github.com/UpStreamPay/purse-securefields-ios/releases/download/v1.10.0/PurseSecureFields.xcframework.zip",
            checksum: "f261ca40bbb3ba27427b4f45423a64897918de25f0386f77de93f3966d28d0ba"
        )
    ]
)
