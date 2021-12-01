//
//  NNError.swift
//  GracefulNetworking
//
//  Created by Oliver Letterer on 30.11.21.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NNError: Error {
    case invalidURL(NNURLConvertible)
    case invalidParameters([String: NNWWWURLFormEncodable])
    case middlewareFailed(URLRequest, NNRequestInterceptor)
    
    case responseStatusCodeFailed(HTTPURLResponse)
}
