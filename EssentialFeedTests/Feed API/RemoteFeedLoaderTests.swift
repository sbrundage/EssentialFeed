//
//  RemoteFeedLoaderTests.swift
//  EssentialFeedTests
//
//  Created by Stephen Brundage on 8/18/26.
//


import Testing
import XCTest
import Foundation
import EssentialFeed

// MARK: - XCTest suite

final class RemoteFeedLoaderXCTests: XCTestCase {
    func test_init_doesNotRequestDataFromURL() {
        let (_, client) = makeSUT()

        XCTAssertTrue(client.requestedURLs.isEmpty)
    }

    func test_load_requestDataFromURL() {
        let url = URL(string: "https://google.com")!
        let (sut, client) = makeSUT(url: url)

        sut.load { _ in }

        XCTAssertEqual(client.requestedURLs, [url])
    }

    func test_loadTwice_requestDataFromURLTwice() {
        let url = URL(string: "https://google.com")!
        let (sut, client) = makeSUT(url: url)

        sut.load { _ in }
        sut.load { _ in }

        XCTAssertEqual(client.requestedURLs, [url, url])
    }

    func test_load_deliversErrorOnClientError() {
        let (sut, client) = makeSUT()

        expect(sut, toCompleteWithResult: failure(.connectivity), when: {
            let clientError = NSError(domain: "Test", code: 0)
            client.complete(with: clientError)
        })
    }

    func test_load_deliversErrorOnNon200HTTPResponse() {
        let (sut, client) = makeSUT()

        [199, 201, 300, 400, 500].enumerated().forEach { index, code in
            expect(sut, toCompleteWithResult: failure(.invalidData), when: {
                let json = Helpers.makeItemsJSON([])
                client.complete(with: code, data: json, at: index)
            })
        }
    }

    func test_load_deliversErrorOn200HTTPResponseWithInvalidJSON() {
        let (sut, client) = makeSUT()

        expect(sut, toCompleteWithResult: failure(.invalidData), when: {
            let invalidJSON = "invalid json".data(using: .utf8)!
            client.complete(with: 200, data: invalidJSON)
        })
    }

    func test_load_deliversNoItemsOn200HTTPResponseWithEmptyJSONList() {
        let (sut, client) = makeSUT()

        expect(sut, toCompleteWithResult: .success([]), when: {
            let emptyListJSON = Helpers.makeItemsJSON([])
            client.complete(with: 200, data: emptyListJSON)
        })
    }

    func test_load_deliversItemsOn200HTTPResponseWithJSONItems() {
        let (sut, client) = makeSUT()
        let item1 = Helpers.makeItem(
            id: UUID(),
            imageURL: .init(string: "www.google.com")!
        )

        let item2 = Helpers.makeItem(
            id: UUID(),
            description: "description",
            location: "location",
            imageURL: .init(string: "www.google.com")!
        )

        let items = [item1.model, item2.model]

        expect(sut, toCompleteWithResult: .success(items), when: {
            let jsonData = Helpers.makeItemsJSON([item1.json, item2.json])
            client.complete(with: 200, data: jsonData)
        })
    }

    func test_load_doesNotDeliverResultAftereSUTInstanceHasBeenDeallocated() {
        let url = URL(string: "http://any-url.com")!
        let client = Helpers.HTTPClientSpy()
        var sut: RemoteFeedLoader? = RemoteFeedLoader(url: url, client: client)

        var capturedResults = [RemoteFeedLoader.Result]()
        sut?.load { capturedResults.append($0) }

        sut = nil
        client.complete(with: 200, data: Helpers.makeItemsJSON([]))

        XCTAssertTrue(capturedResults.isEmpty)
    }
}

// MARK: XCTest Helpers

private extension RemoteFeedLoaderXCTests {
    func makeSUT(
        url: URL = URL(string: "https://google.com")!,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (sut: RemoteFeedLoader, client: Helpers.HTTPClientSpy) {
        let client = Helpers.HTTPClientSpy()
        let sut = RemoteFeedLoader(url: url, client: client)
        trackForMemoryLeaks(sut, file: file, line: line)
        trackForMemoryLeaks(client, file: file, line: line)
        return (sut, client)
    }

    func expect(
        _ sut: RemoteFeedLoader,
        toCompleteWithResult expectedResult: RemoteFeedLoader.Result,
        when action: () -> Void,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let exp = expectation(description: "Wait for load copmletion")
        
        sut.load { receivedResult in
            switch (receivedResult, expectedResult) {
            case let (.success(receivedItems), .success(expectedItems)):
                XCTAssertEqual(receivedItems, expectedItems, file: file, line: line)
            case let (.failure(receivedError as RemoteFeedLoader.Error), .failure(expectedError as RemoteFeedLoader.Error)):
                XCTAssertEqual(receivedError, expectedError, file: file, line: line)
            default:
                XCTFail("Expected result \(expectedResult) got \(receivedResult)", file: file, line: line)
            }
            
            exp.fulfill()
        }
        
        action()
        
        wait(for: [exp], timeout: 1.0)
    }
    
    func failure(_ error: RemoteFeedLoader.Error) -> RemoteFeedLoader.Result { .failure(error) }
}


// MARK: Helpers

private enum Helpers {
    static func makeItem(
        id: UUID,
        description: String? = nil,
        location: String? = nil,
        imageURL: URL
    ) -> (model: FeedItem, json: [String: Any]) {
        let item = FeedItem(id: id, description: description, location: location, imageURL: imageURL)
        let json = [
            "id": id.uuidString,
            "description": description,
            "location": location,
            "image": imageURL.absoluteString
        ].compactMapValues { $0 }
        
        return (item, json)
    }
    
    static func makeItemsJSON(_ items: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["items": items])
    }
    
    class HTTPClientSpy: HTTPClient {
        private var messages = [(url: URL, completion: (HTTPClientResult) -> Void)]()

        var requestedURLs: [URL] {
            messages.map { $0.url }
        }

        func get(from url: URL, completion: @escaping (HTTPClientResult) -> Void) {
            messages.append((url, completion))
        }

        func complete(with error: Error, at index: Int = 0) {
            messages[index].completion(.failure(error))
        }

        func complete(with statusCode: Int, data: Data, at index: Int = 0) {
            let response = HTTPURLResponse(
                url: requestedURLs[index],
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            messages[index].completion(.success(data, response))
        }
    }
    
    //    static func expect(
    //        _ sut: RemoteFeedLoader,
    //        toCompleteWithResult result: RemoteFeedLoader.Result,
    //        when action: () -> Void,
    //        sourceLocation: SourceLocation = #_sourceLocation
    //    ) {
    //        var capturedResults = [RemoteFeedLoader.Result]()
    //        sut.load { capturedResults.append($0) }
    //
    //        action()
    //
    //        #expect(capturedResults == [result], sourceLocation: sourceLocation)
    //    }
}

// MARK: Swift Testing

//class RemoteFeedLoaderTests {
//    private weak var weakSut: RemoteFeedLoader?
//    private weak var weakClient: Helpers.HTTPClientSpy?
//
//    deinit {
//        #expect(weakSut == nil)
//        #expect(weakClient == nil)
//    }
//
//    @Test func test_init_doesNotRequestDataFromURL() async throws {
//        let (_, client) = makeSUT()
//
//        #expect(client.requestedURLs.isEmpty)
//    }
//
//    @Test func test_load_requestDataFromURL() {
//        let url = URL(string: "https://google.com")!
//        let (sut, client) = makeSUT(url: url)
//
//        sut.load { _ in }
//
//        #expect(client.requestedURLs == [url])
//    }
//
//    @Test func test_loadTwice_requestDataFromURLTwice() {
//        let url = URL(string: "https://google.com")!
//        let (sut, client) = makeSUT(url: url)
//
//        sut.load { _ in }
//        sut.load { _ in }
//
//        #expect(client.requestedURLs == [url, url])
//    }
//
//    @Test func test_load_deliversErrorOnClientError() {
//        let (sut, client) = makeSUT()
//
//        expect(sut, toCompleteWithResult: .failure(.connectivity), when: {
//            let clientError = NSError(domain: "Test", code: 0)
//            client.complete(with: clientError)
//        })
//    }
//
//    @Test func test_load_deliversErrorOnNon200HTTPResponse() {
//        let (sut, client) = makeSUT()
//
//        [199, 201, 300, 400, 500].enumerated().forEach { index, code in
//            expect(sut, toCompleteWithResult: .failure(.invalidData), when: {
//                let json = makeItemsJSON([])
//                client.complete(with: code, data: json, at: index)
//            })
//        }
//    }
//
//    @Test func test_load_deliversErrorOn200HTTPResponseWithInvalidJSON() {
//        let (sut, client) = makeSUT()
//
//        expect(sut, toCompleteWithResult: .failure(.invalidData), when: {
//            let invalidJSON = "invalid json".data(using: .utf8)!
//            client.complete(with: 200, data: invalidJSON)
//        })
//    }
//
//    @Test func test_load_deliversNoItemsOn200HTTPResponseWithEmptyJSONList() {
//        let (sut, client) = makeSUT()
//
//        expect(sut, toCompleteWithResult: .success([]), when: {
//            let emptyListJSON = makeItemsJSON([])
//            client.complete(with: 200, data: emptyListJSON)
//        })
//    }
//
//    @Test func test_load_deliversItemsOn200HTTPResponseWithJSONItems() {
//        let (sut, client) = makeSUT()
//        let item1 = makeItem(
//            id: UUID(),
//            imageURL: .init(string: "www.google.com")!
//        )
//
//        let item2 = makeItem(
//            id: UUID(),
//            description: "description",
//            location: "location",
//            imageURL: .init(string: "www.google.com")!
//        )
//
//        let items = [item1.model, item2.model]
//
//        expect(sut, toCompleteWithResult: .success(items), when: {
//            let jsonData = makeItemsJSON([item1.json, item2.json])
//            client.complete(with: 200, data: jsonData)
//        })
//    }
//
//    @Test func test_load_doesNotDeliverResultAftereSUTInstanceHasBeenDeallocated() {
//        let url = URL(string: "http://any-url.com")!
//        let client = Helpers.HTTPClientSpy()
//        var sut: RemoteFeedLoader? = RemoteFeedLoader(url: url, client: client)
//
//        var capturedResults = [RemoteFeedLoader.Result]()
//        sut?.load { capturedResults.append($0) }
//
//        sut = nil
//        client.complete(with: 200, data: makeItemsJSON([]))
//
//        #expect(capturedResults.isEmpty)
//    }
//}

// MARK: Testing Helpers

//private extension RemoteFeedLoaderTests {
//    func makeSUT(
//        url: URL = URL(string: "https://google.com")!
//    ) -> (sut: RemoteFeedLoader, client: Helpers.HTTPClientSpy) {
//        let client = Helpers.HTTPClientSpy()
//        let sut = RemoteFeedLoader(url: url, client: client)
//        self.weakSut = sut
//        self.weakClient = client
//        return (sut, client)
//    }
//
//    func makeItem(
//        id: UUID,
//        description: String? = nil,
//        location: String? = nil,
//        imageURL: URL
//    ) -> (model: FeedItem, json: [String: Any]) {
//        Helpers.makeItem(id: id, description: description, location: location, imageURL: imageURL)
//    }
//
//    func expect(
//        _ sut: RemoteFeedLoader,
//        toCompleteWithResult result: RemoteFeedLoader.Result,
//        when action: () -> Void,
//        sourceLocation: SourceLocation = #_sourceLocation
//    ) {
//        Helpers.expect(sut, toCompleteWithResult: result, when: action)
//    }
//
//    func makeItemsJSON(_ items: [[String: Any]]) -> Data {
//        Helpers.makeItemsJSON(items)
//    }
//}
