//
//  RequestManager.swift
//  GracefulNetworking
//
//  Created by Oliver Letterer on 30.11.21.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import AsyncHTTPClient
import NIO
import NIOHTTP1

extension URLComponents {
    internal init?(string: String, parameters: [String: NNWWWURLFormEncodable]) {
        guard var result = URLComponents(string: string) else {
            return nil
        }
        
        if parameters.count > 0 {
            result.queryItems = result.queryItems ?? []
            
            for (key, value) in parameters {
                guard let items = value.encode(for: key) else {
                    return nil
                }
                
                result.queryItems!.append(contentsOf: items)
            }
        }
        
        self = result
    }
}

private extension Collection where Element == String {
    func qualityEncoded() -> String {
        enumerated().map { index, encoding in
            let quality = 1.0 - (Double(index) * 0.1)
            return "\(encoding);q=\(quality)"
        }.joined(separator: ", ")
    }
}

extension URLRequest {
    internal init(gracefulNetworkingURL url: URL, method: String) {
        self.init(url: url)
        
        self.httpMethod = method
        self.allHTTPHeaderFields = [:]
        
        self.allHTTPHeaderFields!["Accept-Encoding"] = defaultAcceptEncoding
        self.allHTTPHeaderFields!["User-Agent"] = self.defaultUserAgent
        self.allHTTPHeaderFields!["Accept-Language"] = Locale.preferredLanguages.prefix(6).qualityEncoded()
    }
    
    private var defaultAcceptEncoding: String {
        let encodings: [String] = [ "identity" ]
        return encodings.qualityEncoded()
    }
    
    private var defaultUserAgent: String {
        let info = Bundle.main.infoDictionary
        let executable = (info?["CFBundleExecutable"] as? String) ??
        (ProcessInfo.processInfo.arguments.first?.split(separator: "/").last.map(String.init)) ??
        "Unknown"
        let bundle = info?["CFBundleIdentifier"] as? String ?? "Unknown"
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let appBuild = info?["CFBundleVersion"] as? String ?? "Unknown"
        
        let osNameVersion: String = {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            let osName: String = {
#if os(iOS)
#if targetEnvironment(macCatalyst)
                return "macOS(Catalyst)"
#else
                return "iOS"
#endif
#elseif os(watchOS)
                return "watchOS"
#elseif os(tvOS)
                return "tvOS"
#elseif os(macOS)
                return "macOS"
#elseif os(Linux)
                return "Linux"
#elseif os(Windows)
                return "Windows"
#else
                return "Unknown"
#endif
            }()
            
            return "\(osName) \(versionString)"
        }()
        
        return "\(executable)/\(appVersion) (\(bundle); build:\(appBuild); \(osNameVersion)) GracefulNetworking"
    }
}

extension HTTPClient.Request {
    internal init(request: URLRequest) {
        let headers = (request.allHTTPHeaderFields ?? [:]).map({ $0 })
        
        if let body = request.httpBody {
            try! self.init(url: request.url!.absoluteString, method: .init(rawValue: request.httpMethod!), headers: .init(headers), body: .data(body))
        } else {
            if let bodyStream = request.httpBodyStream {
                fatalError("httpBodyStream not supported at the moment \(bodyStream)")
            } else {
                try! self.init(url: request.url!.absoluteString, method: .init(rawValue: request.httpMethod!), headers: .init(headers), body: nil)
            }
        }
    }
}

extension HTTPURLResponse {
    internal convenience init(request: URLRequest, response: HTTPClient.Response) {
        var headers: [String: String] = [:]
        
        response.headers.forEach { (key, value) in
            headers[key] = value
        }
        
        self.init(url: request.url!, statusCode: Int(response.status.code), httpVersion: response.version.description, headerFields: headers)!
    }
    
    internal convenience init(request: URLRequest, response: HTTPResponseHead) {
        var headers: [String: String] = [:]
        
        response.headers.forEach { (key, value) in
            headers[key] = value
        }
        
        self.init(url: request.url!, statusCode: Int(response.status.code), httpVersion: response.version.description, headerFields: headers)!
    }
}

extension HTTPClient.Response {
    internal var responseData: Data? {
        if var body = body, body.readableBytes > 0, let bytes = body.readBytes(length: body.readableBytes) {
            return Data(bytes)
        } else {
            return nil
        }
    }
}

extension String.Encoding {
    internal init?(ianaCharsetName name: String) {
        switch name.lowercased() {
        case "utf-8":
            self = .utf8
        case "iso-8859-1":
            self = .isoLatin1
        case "unicode-1-1", "iso-10646-ucs-2", "utf-16":
            self = .utf16
        case "utf-16be":
            self = .utf16BigEndian
        case "utf-16le":
            self = .utf16LittleEndian
        case "utf-32":
            self = .utf32
        case "utf-32be":
            self = .utf32BigEndian
        case "utf-32le":
            self = .utf32LittleEndian
        default:
            return nil
        }
    }
}

public struct NN {
    public static let shared: RequestManager = RequestManager()
    
    public class RequestManager: RequestManagerImplementation {
        public struct RequestProjection<Manager: RequestManager> {
            let requestManager: Manager
            
            enum State {
                case request(URLRequest)
                case failed(Error)
            }
            
            let request: State
            
            public func getRequest() throws -> URLRequest {
                switch request {
                case let .request(request):
                    return request
                case let .failed(error):
                    throw error
                }
            }
        }
        
        public let eventLoopGroup: MultiThreadedEventLoopGroup
        let httpClient: HTTPClient
        
        public let acceptableStatusCodes: Set<Int>
        public var dateCodingStrategyByHost: [String: (encoding: JSONEncoder.DateEncodingStrategy, decoding: JSONDecoder.DateDecodingStrategy)] = [:]
        
        public init(eventLoopGroup: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2), configuration: HTTPClient.Configuration = HTTPClient.Configuration(timeout: .init(connect: .seconds(60), read: .seconds(10))), acceptableStatusCodes: Set<Int> = Set(200..<400)) {
            var copy = configuration
            copy.httpVersion = .http1Only
            
            self.eventLoopGroup = eventLoopGroup
            self.httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup), configuration: copy)
            self.acceptableStatusCodes = acceptableStatusCodes
        }
        
        deinit {
            let eventLoopGroup = self.eventLoopGroup
            let httpClient = self.httpClient
            
            let finish: () -> Void = {
                try! httpClient.syncShutdown()
                let _ = eventLoopGroup
            }
            
            if Thread.current.isMainThread {
                finish()
            } else {
                DispatchQueue.main.async(execute: finish)
            }
        }
    }
}

public protocol RequestManagerImplementation where Self: NN.RequestManager {
    
}

extension RequestManagerImplementation {
    public func request(_ request: URLRequest) -> RequestProjection<Self> {
        return RequestProjection(requestManager: self, request: .request(request))
    }
    
    public func get(_ url: NNURLConvertible, parameters: [String: NNWWWURLFormEncodable] = [:], headers: [(key: String, value: String)] = []) -> RequestProjection<Self> {
        guard let url = url.convertToURL else {
            return RequestProjection(requestManager: self, request: .failed(NNError.invalidURL(url)))
        }
        
        guard let components = URLComponents(string: url.absoluteString, parameters: parameters), let url = components.url else {
            return RequestProjection(requestManager: self, request: .failed(NNError.invalidParameters(parameters)))
        }
        
        var request = URLRequest(gracefulNetworkingURL: url, method: "GET")
        
        headers.forEach { key, value in
            request.allHTTPHeaderFields![key] = value
        }
        
        return self.request(request)
    }
    
    public func post(_ url: NNURLConvertible, parameters: [String: NNWWWURLFormEncodable] = [:], headers: [(key: String, value: String)] = []) -> RequestProjection<Self> {
        return self.requestBody(method: "POST", url: url, parameters: parameters, headers: headers)
    }
    
    public func put(_ url: NNURLConvertible, parameters: [String: NNWWWURLFormEncodable] = [:], headers: [(key: String, value: String)] = []) -> RequestProjection<Self> {
        return self.requestBody(method: "PUT", url: url, parameters: parameters, headers: headers)
    }
    
    public func patch(_ url: NNURLConvertible, parameters: [String: NNWWWURLFormEncodable] = [:], headers: [(key: String, value: String)] = []) -> RequestProjection<Self> {
        return self.requestBody(method: "PATCH", url: url, parameters: parameters, headers: headers)
    }
    
    public func post<T: Encodable>(_ url: NNURLConvertible, body: T, encoder: JSONEncoder? = nil, headers: [(key: String, value: String)] = []) -> RequestProjection<Self> {
        let encoder = encoder ?? self.encoder(forHost: url.convertToURL?.host)
        
        do {
            let data = try encoder.encode(body)
            return self.requestBody(method: "POST", url: url, headers: headers, body: ("application/json; charset=utf-8", data))
        } catch {
            return RequestProjection(requestManager: self, request: .failed(error))
        }
    }
    
    public func put<T: Encodable>(_ url: NNURLConvertible, body: T, encoder: JSONEncoder? = nil, headers: [(key: String, value: String)] = []) -> RequestProjection<Self> {
        let encoder = encoder ?? self.encoder(forHost: url.convertToURL?.host)
        
        do {
            let data = try encoder.encode(body)
            return self.requestBody(method: "PUT", url: url, headers: headers, body: ("application/json; charset=utf-8", data))
        } catch {
            return RequestProjection(requestManager: self, request: .failed(error))
        }
    }
    
    public func patch<T: Encodable>(_ url: NNURLConvertible, body: T, encoder: JSONEncoder? = nil, headers: [(key: String, value: String)] = []) -> RequestProjection<Self> {
        let encoder = encoder ?? self.encoder(forHost: url.convertToURL?.host)
        
        do {
            let data = try encoder.encode(body)
            return self.requestBody(method: "PATCH", url: url, headers: headers, body: ("application/json; charset=utf-8", data))
        } catch {
            return RequestProjection(requestManager: self, request: .failed(error))
        }
    }
    
    public func delete(_ url: NNURLConvertible, parameters: [String: NNWWWURLFormEncodable] = [:], headers: [(key: String, value: String)] = []) -> RequestProjection<Self> {
        guard let url = url.convertToURL else {
            return RequestProjection(requestManager: self, request: .failed(NNError.invalidURL(url)))
        }
        
        guard let components = URLComponents(string: url.absoluteString, parameters: parameters), let url = components.url else {
            return RequestProjection(requestManager: self, request: .failed(NNError.invalidParameters(parameters)))
        }
        
        var request = URLRequest(gracefulNetworkingURL: url, method: "DELETE")
        headers.forEach { key, value in
            request.allHTTPHeaderFields![key] = value
        }
        
        return self.request(request)
    }
}

extension RequestManagerImplementation {
    private func requestBody(method: String, url: NNURLConvertible, parameters: [String: NNWWWURLFormEncodable], headers: [(key: String, value: String)]) -> RequestProjection<Self> {
        guard let url = url.convertToURL else {
            return RequestProjection(requestManager: self, request: .failed(NNError.invalidURL(url)))
        }
        
        var components: [String] = []
        for (key, value) in parameters {
            guard let items = value.encode(for: key) else {
                return RequestProjection(requestManager: self, request: .failed(NNError.invalidParameters(parameters)))
            }
            
            items.forEach { item in
                components.append(item.name + "=" + (item.value ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)
            }
        }
        
        guard let body = components.joined(separator: "&").data(using: .utf8) else {
            return RequestProjection(requestManager: self, request: .failed(NNError.invalidParameters(parameters)))
        }
        
        var request = URLRequest(gracefulNetworkingURL: url, method: method)
        request.allHTTPHeaderFields!["Content-Length"] = String(body.count)
        request.allHTTPHeaderFields!["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
        
        request.httpBody = body
        
        headers.forEach { key, value in
            request.allHTTPHeaderFields![key] = value
        }
        
        return RequestProjection(requestManager: self, request: .request(request))
    }
    
    private func requestBody(method: String, url: NNURLConvertible, headers: [(key: String, value: String)], body: (String, Data)) -> RequestProjection<Self> {
        guard let url = url.convertToURL else {
            return RequestProjection(requestManager: self, request: .failed(NNError.invalidURL(url)))
        }
        
        var request = URLRequest(gracefulNetworkingURL: url, method: method)
        request.allHTTPHeaderFields!["Content-Length"] = String(body.1.count)
        request.allHTTPHeaderFields!["Content-Type"] = body.0
        
        request.httpBody = body.1
        
        headers.forEach { key, value in
            request.allHTTPHeaderFields![key] = value
        }
        
        return RequestProjection(requestManager: self, request: .request(request))
    }
    
    private func encoder(forHost host: String?) -> JSONEncoder {
        let encoder = JSONEncoder()
        
        if let host = host, let strategies = dateCodingStrategyByHost[host] {
            encoder.dateEncodingStrategy = strategies.encoding
        } else {
            encoder.dateEncodingStrategy = .iso8601
        }
        
        return encoder
    }
}

extension RequestManagerImplementation {
    public func download(_ url: NNURLConvertible, parameters: [String: NNWWWURLFormEncodable] = [:], headers: [(key: String, value: String)] = [], destination: URL, downloadProgress: ((HTTPURLResponse, Int, Int?) -> Void)? = nil, completion: @escaping (RequestProjection<Self>.Response<()>?, Error?) -> Void) {
        self.get(url, parameters: parameters, headers: headers).download(destination: destination, downloadProgress: downloadProgress, completion: completion)
    }
    
    public func download(_ url: NNURLConvertible, parameters: [String: NNWWWURLFormEncodable] = [:], headers: [(key: String, value: String)] = [], destination: URL) async throws -> RequestProjection<Self>.Response<()> {
        return try await self.get(url, parameters: parameters, headers: headers).download(destination: destination)
    }
}

public extension NN.RequestManager.RequestProjection {
    func with(_ middlewares: NNRequestInterceptor...) -> NN.RequestManager.RequestProjection<Manager> {
        switch request {
        case let .failed(error):
            return .init(requestManager: requestManager, request: .failed(error))
        case var .request(request):
            for middleware in middlewares {
                guard let adapted = middleware.adapt(request) else {
                    return .init(requestManager: requestManager, request: .failed(NNError.middlewareFailed(request, middleware)))
                }
                
                request = adapted
            }
            
            return .init(requestManager: requestManager, request: .request(request))
        }
    }
}

public extension NN.RequestManager.RequestProjection {
    struct Response<T> {
        public let request: URLRequest
        public let response: HTTPURLResponse
        public let data: Data?
        public let body: T
    }
    
    func response(completion: @escaping (Response<Data?>?, Error?) -> Void) {
        switch request {
        case let .request(request):
            requestManager.httpClient.execute(request: .init(request: request)).whenComplete { result in
                switch result {
                case let .failure(error):
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                case let .success(clientResponse):
                    let response = HTTPURLResponse(request: request, response: clientResponse)
                    
                    guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
                        let data = clientResponse.responseData
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: data, body: nil), NNError.responseStatusCodeFailed(response))
                        }
                        return
                    }
                    
                    let data: Data? = clientResponse.responseData
                    DispatchQueue.main.async {
                        completion(.init(request: request, response: response, data: data, body: data), nil)
                    }
                }
            }
        case let .failed(error):
            completion(nil, error)
        }
    }
    
    func get() async throws -> Response<Data?> {
        let request = try getRequest()
        let clientResponse = try await requestManager.httpClient.execute(request: .init(request: request)).get()
        let response = HTTPURLResponse(request: request, response: clientResponse)
        
        guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
            throw NNError.responseStatusCodeFailed(response)
        }
        
        let data: Data? = clientResponse.responseData
        return .init(request: request, response: response, data: data, body: data)
    }
    
    func responseData(completion: @escaping (Response<Data?>?, Error?) -> Void) {
        switch request {
        case let .request(request):
            requestManager.httpClient.execute(request: .init(request: request)).whenComplete { result in
                switch result {
                case let .failure(error):
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                case let .success(clientResponse):
                    let response = HTTPURLResponse(request: request, response: clientResponse)
                    
                    guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
                        let data = clientResponse.responseData
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: data, body: nil), NNError.responseStatusCodeFailed(response))
                        }
                        return
                    }
                    
                    guard let data: Data = clientResponse.responseData else {
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: nil, body: nil), URLError(.badServerResponse))
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        completion(.init(request: request, response: response, data: data, body: data), nil)
                    }
                }
            }
        case let .failed(error):
            completion(nil, error)
        }
    }
    
    func responseData() async throws -> Response<Data> {
        let request = try getRequest()
        let clientResponse = try await requestManager.httpClient.execute(request: .init(request: request)).get()
        let response = HTTPURLResponse(request: request, response: clientResponse)
        
        guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
            throw NNError.responseStatusCodeFailed(response)
        }
        
        guard let data: Data = clientResponse.responseData else {
            throw URLError(.badServerResponse)
        }
        
        return .init(request: request, response: response, data: data, body: data)
    }
    
    func responseString(encoding: String.Encoding? = nil, completion: @escaping (Response<String?>?, Error?) -> Void) {
        switch request {
        case let .request(request):
            requestManager.httpClient.execute(request: .init(request: request)).whenComplete { result in
                switch result {
                case let .failure(error):
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                case let .success(clientResponse):
                    let response = HTTPURLResponse(request: request, response: clientResponse)
                    
                    guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
                        let data = clientResponse.responseData
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: data, body: nil), NNError.responseStatusCodeFailed(response))
                        }
                        return
                    }
                    
                    guard let data: Data = clientResponse.responseData else {
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: nil, body: nil), URLError(.badServerResponse))
                        }
                        return
                    }
                    
                    let encoding: String.Encoding = encoding ?? response.textEncodingName.flatMap({ String.Encoding(ianaCharsetName: $0) }) ?? .utf8
                    
                    guard let string = String(data: data, encoding: encoding) else {
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: data, body: nil), URLError(.badServerResponse))
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        completion(.init(request: request, response: response, data: data, body: string), nil)
                    }
                }
            }
        case let .failed(error):
            completion(nil, error)
        }
    }
    
    func responseString(encoding: String.Encoding? = nil) async throws -> Response<String> {
        let request = try getRequest()
        let clientResponse = try await requestManager.httpClient.execute(request: .init(request: request)).get()
        let response = HTTPURLResponse(request: request, response: clientResponse)
        
        guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
            throw NNError.responseStatusCodeFailed(response)
        }
        
        guard let data: Data = clientResponse.responseData else {
            throw URLError(.badServerResponse)
        }
        
        let encoding: String.Encoding = encoding ?? response.textEncodingName.flatMap({ String.Encoding(ianaCharsetName: $0) }) ?? .utf8
        
        guard let string = String(data: data, encoding: encoding) else {
            throw URLError(.badServerResponse)
        }
        
        return .init(request: request, response: response, data: data, body: string)
    }
    
    private func decoder(forHost host: String?) -> JSONDecoder {
        let decoder = JSONDecoder()
        
        if let host = host, let strategies = requestManager.dateCodingStrategyByHost[host] {
            decoder.dateDecodingStrategy = strategies.decoding
        } else {
            decoder.dateDecodingStrategy = .iso8601
        }
        
        return decoder
    }
    
    func responseDecodable<T: Decodable>(of: T.Type, decoder: JSONDecoder? = nil, completion: @escaping (Response<T?>?, Error?) -> Void) {
        switch request {
        case let .request(request):
            let jsonDecoder = decoder ?? self.decoder(forHost: request.url!.host)
            
            requestManager.httpClient.execute(request: .init(request: request)).whenComplete { result in
                switch result {
                case let .failure(error):
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                case let .success(clientResponse):
                    let response = HTTPURLResponse(request: request, response: clientResponse)
                    
                    guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
                        let data = clientResponse.responseData
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: data, body: nil), NNError.responseStatusCodeFailed(response))
                        }
                        return
                    }
                    
                    guard let data: Data = clientResponse.responseData else {
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: nil, body: nil), URLError(.badServerResponse))
                        }
                        return
                    }
                    
                    do {
                        let result = try jsonDecoder.decode(T.self, from: data)
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: data, body: result), nil)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: data, body: nil), error)
                        }
                    }
                }
            }
        case let .failed(error):
            completion(nil, error)
        }
    }
    
    func responseDecodable<T: Decodable>(of: T.Type, decoder: JSONDecoder? = nil) async throws -> Response<T> {
        let request = try getRequest()
        let jsonDecoder = decoder ?? self.decoder(forHost: request.url!.host)
        
        let clientResponse = try await requestManager.httpClient.execute(request: .init(request: request)).get()
        let response = HTTPURLResponse(request: request, response: clientResponse)
        
        guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
            throw NNError.responseStatusCodeFailed(response)
        }
        
        guard let data: Data = clientResponse.responseData else {
            throw URLError(.badServerResponse)
        }
        
        let result = try jsonDecoder.decode(T.self, from: data)
        return .init(request: request, response: response, data: data, body: result)
    }
    
    func download(destination: URL, downloadProgress: ((HTTPURLResponse, Int, Int?) -> Void)? = nil, completion: @escaping (Response<()>?, Error?) -> Void) {
        switch request {
        case let .request(request):
            var temporary: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            while FileManager.default.fileExists(atPath: temporary.path) {
                temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            }
            
            var responseHead: HTTPResponseHead? = nil
            let delegate = try! FileDownloadDelegate(path: temporary.path, reportHead: { head in
                responseHead = head
            }, reportProgress: { progress in
                if let downloadProgress = downloadProgress, let responseHead = responseHead {
                    let response = HTTPURLResponse(request: request, response: responseHead)
                    let received = progress.receivedBytes
                    let total = progress.totalBytes
                    
                    DispatchQueue.main.async {
                        downloadProgress(response, received, total)
                    }
                }
            })
            
            requestManager.httpClient.execute(request: .init(request: request), delegate: delegate).futureResult.whenComplete { result in
                defer { let _ = self }
                
                switch result {
                case let .failure(error):
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                case .success:
                    guard let responseHead = responseHead else {
                        DispatchQueue.main.async {
                            completion(nil, URLError(.badServerResponse))
                        }
                        return
                    }
                    
                    let response = HTTPURLResponse(request: request, response: responseHead)
                    
                    guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: nil, body: ()), NNError.responseStatusCodeFailed(response))
                        }
                        return
                    }
                    
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            let _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                        } else {
                            try FileManager.default.moveItem(at: temporary, to: destination)
                        }
                        
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: nil, body: ()), nil)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            completion(.init(request: request, response: response, data: nil, body: ()), error)
                        }
                    }
                }
                
                let _ = delegate
            }
        case let .failed(error):
            completion(nil, error)
        }
    }
    
    func download(destination: URL) async throws -> Response<()> {
        let request = try getRequest()
        
        var temporary: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        while FileManager.default.fileExists(atPath: temporary.path) {
            temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        }
        
        var responseHead: HTTPResponseHead? = nil
        let delegate = try! FileDownloadDelegate(path: temporary.path, reportHead: { head in
            responseHead = head
        })
        
        let _ = try await requestManager.httpClient.execute(request: .init(request: request), delegate: delegate).futureResult.get()
        
        guard let responseHead = responseHead else {
            throw URLError(.badServerResponse)
        }
        
        let response = HTTPURLResponse(request: request, response: responseHead)
        
        guard requestManager.acceptableStatusCodes.contains(response.statusCode) else {
            throw NNError.responseStatusCodeFailed(response)
        }
        
        if FileManager.default.fileExists(atPath: destination.path) {
            let _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        
        return .init(request: request, response: response, data: nil, body: ())
    }
}
