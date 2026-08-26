//
//  FeedLoader.swift
//  EssentialFeed
//
//  Created by Stephen Brundage on 8/18/26.
//

import Foundation

public enum LoadFeedResult {
    case success([FeedItem])
    case failure(Error)
}

public protocol FeedLoader {
    func load(completion: @escaping (LoadFeedResult) -> Void)
}
