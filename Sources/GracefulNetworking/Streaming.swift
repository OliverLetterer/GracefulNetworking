//
//  Streaming.swift
//  GracefulNetworking
//
//  Created by Oliver Letterer on 11.12.21.
//

import Foundation

import AsyncHTTPClient
import NIO
import NIOHTTP1

extension NN {
    public class StreamingRequestManager: RequestManager {
        
    }
}

public protocol StreamHandle: AnyObject {
    func cancel()
}

public extension NN.RequestManager.RequestProjection where Manager: NN.StreamingRequestManager {
    private class StreamingDelegate: HTTPClientResponseDelegate {
        typealias Response = ()
        
        private var buffer: Data = Data()
        
        private let request: URLRequest
        private let encoding: String.Encoding?
        private var response: HTTPURLResponse? = nil
        
        private var _callback: ((Result<String, Error>) -> Void)?
        private let lock: NSLock = NSLock()
        
        var callback: ((Result<String, Error>) -> Void)? {
            get {
                lock.lock()
                defer { lock.unlock() }
                
                return _callback
            }
            
            set {
                lock.lock()
                defer { lock.unlock() }
                
                _callback = newValue
            }
        }
        
        init(request: URLRequest, encoding: String.Encoding?, callback: @escaping (Result<String, Error>) -> Void) {
            self.request = request
            self.encoding = encoding
            self._callback = callback
        }
        
        func didReceiveHead(task: HTTPClient.Task<()>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
            self.response = .init(request: request, response: head)
            return task.eventLoop.makeSucceededVoidFuture()
        }
        
        func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
            guard let response = response else {
                return task.eventLoop.makeSucceededVoidFuture()
            }
            
            var copy = buffer
            if copy.readableBytes > 0, let bytes = copy.readBytes(length: buffer.readableBytes) {
                self.buffer.append(Data(bytes))
                let encoding: String.Encoding = self.encoding ?? response.textEncodingName.flatMap({ String.Encoding(ianaCharsetName: $0) }) ?? .utf8
                
                var index: Int = 0
                while index < self.buffer.count - 1 {
                    guard self.buffer[index] == 13 else {
                        index += 1
                        continue
                    }
                    
                    index += 1
                    guard self.buffer[index] == 10 else {
                        index += 1
                        continue
                    }
                    
                    let data = self.buffer[..<(index - 1)]
                    
                    if let string = String(data: data, encoding: encoding), !string.isEmpty {
                        callback?(.success(string))
                    }
                    
                    index = 0
                    self.buffer.removeSubrange(...index)
                }
            }
            
            return task.eventLoop.makeSucceededVoidFuture()
        }
        
        func didReceiveError(task: HTTPClient.Task<()>, _ error: Error) {
            callback?(.failure(error))
        }
        
        func didFinishRequest(task: HTTPClient.Task<()>) throws -> () {
            callback?(.failure(URLError(.badServerResponse)))
        }
    }
    
    private class StreamingHandle: StreamHandle {
        private let task: HTTPClient.Task<()>
        private let delegate: StreamingDelegate
        
        init(task: HTTPClient.Task<()>, delegate: StreamingDelegate) {
            self.task = task
            self.delegate = delegate
        }
        
        deinit {
            task.cancel()
        }
        
        func cancel() {
            delegate.callback = nil
            task.cancel()
        }
    }
    
    func streamString(encoding: String.Encoding? = nil, callback: @escaping (Result<String, Error>) -> Void) throws -> StreamHandle {
        switch request {
        case let .request(request):
            let delegate = StreamingDelegate(request: request, encoding: encoding) { result in
                DispatchQueue.main.async {
                    callback(result)
                }
            }
            
            let task = requestManager.httpClient.execute(request: .init(request: request), delegate: delegate, deadline: .now() + .hours(10 * 365 * 24))
            return StreamingHandle(task: task, delegate: delegate)
        case let .failed(error):
            throw error
        }
    }
}

