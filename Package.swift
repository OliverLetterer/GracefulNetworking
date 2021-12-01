// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GracefulNetworking",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "GracefulNetworking",
            targets: ["GracefulNetworking"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "GracefulNetworking",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]
        ),
    ]
)
