//
//  NNRequestInterceptor.swift
//  GracefulNetworking
//
//  Created by Oliver Letterer on 30.11.21.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol NNRequestInterceptor {
    func adapt(_ urlRequest: URLRequest) -> URLRequest?
}
