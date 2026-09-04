//
//  HTTPClient.swift
//  EssentialFeed
//
//  Created by Stephen Brundage on 8/23/26.
//

import Foundation

public enum HTTPClientResult {
    case success(Data, HTTPURLResponse)
    case failure(Error)
}

public protocol HTTPClient {
    func get(from url: URL, completion: @escaping (HTTPClientResult) -> Void)
}
