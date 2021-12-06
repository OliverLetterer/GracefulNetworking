# Graceful Networking

## Elegant Networking in Swift

[![Platforms](https://img.shields.io/badge/Platforms-macOS_iOS_tvOS_watchOS_Linux-green?style=flat-square)](https://img.shields.io/badge/Platforms-macOS_iOS_tvOS_watchOS_Linux-green?style=flat-square)
[![Swift](https://img.shields.io/badge/Swift-5.5-green?style=flat-square)](https://img.shields.io/badge/Swift-5.5-green?style=flat-square)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-critical?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-critical?style=flat-square)

Based on [AsyncHTTPClient](https://github.com/swift-server/async-http-client).

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler. It is in early development, but Graceful Networking does support its use on supported platforms.

Once you have your Swift package set up, adding Graceful Networking as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .package(url: "https://github.com/OliverLetterer/GracefulNetworking.git", .upToNextMajor(from: "0.1.0"))
]
```

### Credit

Graceful Networking is slightly inspired by [github.com/Alamofire/Alamofire](https://github.com/Alamofire/Alamofire).

### Making requests

```swift
NN.shared.get("https://jsonplaceholder.typicode.com/posts").response { response, error in
    debugPrint(response)
}
```

```swift
struct PostResponse: Codable {
    var id: Int
    var title: String
    var body: String
    var userId: String
}

let parameters: [String: NNWWWURLFormEncodable] = [
    "title": "title",
    "body": "body",
    "userId": "5"
]

NN.shared.post("https://jsonplaceholder.typicode.com/posts", parameters: parameters).responseDecodable(of: PostResponse.self) { response, error in
    debugPrint(response)
}
```

### Downloading data to a file

```swift
let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("image.png")
NN.shared.download("https://httpbin.org/image/png", destination: url) { respose, error in
    debugPrint(respose)
}
```
