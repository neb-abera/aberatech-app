// swift-tools-version: 6.2
import PackageDescription

// The app's logic, with no Apple-only framework in it: the sign-in, the
// abera.tech API, and the Apple Health weigh-in sync. It builds and tests on
// Linux in the Swift image (`make test`) and on macOS in CI.
// ASWebAuthenticationSession, HealthKit and the Keychain stay in the app
// target, behind the protocols in Ports.swift.
let package = Package(
    name: "AberaCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AberaCore", targets: ["AberaCore"])
    ],
    dependencies: [
        // SHA-256 for the PKCE challenge on Linux. Apple platforms use CryptoKit.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "AberaCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ]
        ),
        .testTarget(name: "AberaCoreTests", dependencies: ["AberaCore"])
    ],
    swiftLanguageModes: [.v6]
)
