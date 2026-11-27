// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PurseSecureFields",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "PurseSecureFields", type: .dynamic, targets: ["PurseSecureFields"]),
        // Optional, for Purse 3DS only: a merchant who does not use it links no Netcetera code.
        // Linking it is the whole switch — Secure Fields discovers the provider at runtime.
        .library(name: "PurseSecureFields3DS", targets: ["PurseSecureFields3DS"])
    ],
    targets: [
        .target(name: "PurseSecureFields", resources: [.process("Resources")]),
        .target(
            name: "PurseSecureFields3DS",
            dependencies: ["PurseSecureFields", "ThreeDS_SDK"]
        ),
        // The Netcetera 3DS Mobile SDK. Netcetera publish this binary themselves, unauthenticated,
        // on their public Maven repository, and allow redistribution inside an integrator's SDK
        // (their FAQ, "API Key & Distribution"). Their own SPM package (github.com/ios-3ds-sdk/SPM)
        // is the same `.binaryTarget` but stuck on 2.6.00, which is not API-compatible with 2.7.x.
        // No credential is involved, and no API key: that is runtime configuration.
        .binaryTarget(
            name: "ThreeDS_SDK",
            url: "https://nexus.extranet.netcetera.biz/nexus/repository/public-repository-maven/com/netcetera/nca-341-2/3ds-sdk/ios/release/2.7.01/ThreeDS_SDK.zip",
            checksum: "3799efeba47f09a4670046830240ac4fcc31453ef68e0bcc821e37e650b0e3ac"
        ),
        .testTarget(
            name: "PurseSecureFieldsTests",
            dependencies: ["PurseSecureFields"]
        )
    ]
)
