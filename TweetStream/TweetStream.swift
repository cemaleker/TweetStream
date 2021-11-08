import Foundation
import Combine
import UIKit

struct TweetResponse: Codable {
    let data: Tweet
}

struct Tweet: Codable {
    let id: String
    let text: String
}

extension Tweet: Equatable { }

final class TweetStreamSession: NSObject {
    enum Error: Swift.Error {
        case stringConversionFailure
        case dataConversionFailure(Swift.Error, String)
    }
    
    private var session: URLSession!
    private var dataTask: URLSessionDataTask?

    private let decoder = JSONDecoder()
    private let dataPublisher = PassthroughSubject<Data, Swift.Error>()
    private let tweetPublisher = PassthroughSubject<[Tweet], Never>()
    private(set) var subject: AnyPublisher<[Tweet], Never>!
    
    override init () {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        subject = Deferred { [unowned self] () -> AnyPublisher<[Tweet], Never> in
            let task = makeTask()
            self.dataTask = task
            task.resume()
            return makeTweetPublisher()
        }.share().eraseToAnyPublisher()
    }
    
    private func makeTask() -> URLSessionDataTask {
        var request = URLRequest(url: URL(string: "https://api.twitter.com/2/tweets/sample/stream?expansions=author_id")!)
        request.setValue(
            "Bearer \(ProcessInfo.processInfo.environment["BEARER_TOKEN"] as! String)",
            forHTTPHeaderField: "Authorization"
        )
        return self.session.dataTask(with: request)
    }
    
    private func convertDataToTweetList(_ data: Data) throws -> [Tweet] {
        func convertDataToTweet(_ data: Data) throws -> Tweet {
            do {
                let tweetResponse = try decoder.decode(TweetResponse.self, from: data)
                return tweetResponse.data
            } catch {
                throw Error.dataConversionFailure(error, String(data: data, encoding: .unicode) ?? "unknown")
            }
        }
        
        guard let string = String(data: data, encoding: .utf8) else { throw Error.stringConversionFailure }
        let slices = string.split(whereSeparator: \.isNewline)
        return try slices
            .map({ slice -> Data in
                if let data = String(slice).data(using: .utf8) {
                    return data
                }
                throw Error.stringConversionFailure
            })
            .map(convertDataToTweet)
    }
    
    func makeTweetPublisher() -> AnyPublisher<[Tweet], Never> {
        dataPublisher
            .tryMap(convertDataToTweetList)
            .catch({ error -> Just<[Tweet]> in
                print(">>>> Error: \(error)")
                return Just([])
            })
            .eraseToAnyPublisher()
    }
}

extension TweetStreamSession: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask == self.dataTask else { return }
        
        dataPublisher.send(data)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        guard dataTask == self.dataTask else { return }
        
        dataPublisher.send(completion: error.map({ .failure($0) }) ?? .finished)
    }
}
