//
//  NNURLConvertible.swift
//  GracefulNetworking
//
//  Created by Oliver Letterer on 30.11.21.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol NNURLConvertible {
    var convertToURL: URL? { get }
}

extension String: NNURLConvertible {
    public var convertToURL: URL? {
        return URL(string: self)
    }
}

extension URL: NNURLConvertible {
    public var convertToURL: URL? {
        return self
    }
}
