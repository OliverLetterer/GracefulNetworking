//
//  WWWURLFormEncodable.swift
//  GracefulNetworking
//
//  Created by Oliver Letterer on 30.11.21.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol NNWWWURLFormEncodable {
    func encode(for key: String) -> [URLQueryItem]?
}

extension String: NNWWWURLFormEncodable {
    public func encode(for key: String) -> [URLQueryItem]? {
        return [ URLQueryItem(name: key, value: self) ]
    }
}

extension Bool: NNWWWURLFormEncodable {
    public func encode(for key: String) -> [URLQueryItem]? {
        return [ URLQueryItem(name: key, value: self ? "true" : "false") ]
    }
}

extension Int: NNWWWURLFormEncodable {
    public func encode(for key: String) -> [URLQueryItem]? {
        return [ URLQueryItem(name: key, value: String(self)) ]
    }
}

extension Double: NNWWWURLFormEncodable {
    public func encode(for key: String) -> [URLQueryItem]? {
        return [ URLQueryItem(name: key, value: String(self)) ]
    }
}

extension Array: NNWWWURLFormEncodable where Element: NNWWWURLFormEncodable {
    public func encode(for key: String) -> [URLQueryItem]? {
        var result: [URLQueryItem] = []
        
        for element in self {
            guard let components = element.encode(for: key + "[]") else {
                return nil
            }
            
            result.append(contentsOf: components)
        }
        
        return result
    }
}

extension Dictionary: NNWWWURLFormEncodable where Key == String, Value: NNWWWURLFormEncodable {
    public func encode(for key: String) -> [URLQueryItem]? {
        var result: [URLQueryItem] = []
        
        for (otherKey, value) in self {
            guard let componenets = value.encode(for: key + "[\(otherKey)]") else {
                return nil
            }
            
            result.append(contentsOf: componenets)
        }
        
        return result
    }
}
