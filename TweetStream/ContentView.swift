import Foundation
import SwiftUI
import Combine

final class ContentModel: ObservableObject {
    @Published var tweets: [Tweet] = []
    @Published var tweetPerSecond: Int = 0
    
    private let stream = TweetStreamSession()
    private var cancellables = Set<AnyCancellable>()
    
    func startStream() {
        stream.subject
            .collect(.byTimeOrCount(RunLoop.main, .seconds(1.0), 100))
            .sink(receiveValue: { [weak self] tweets in
                let flatTweets = tweets.flatMap({ $0 })
                self?.tweets.insert(contentsOf: flatTweets, at: 0)
            })
            .store(in: &cancellables)
        
        stream.subject
            .collect(.byTime(DispatchQueue.main, .seconds(1.0)))
            .sink(receiveValue: { [weak self] tweets in
                self?.tweetPerSecond = tweets.flatMap({ $0 }).count
            })
            .store(in: &cancellables)
    }
}

struct TweetListView: View {
    @ObservedObject private var viewModel = ContentModel()
    
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10.0) {
                Text("Tweet/sec \(viewModel.tweetPerSecond)")
                Text("Total \(viewModel.tweets.count) tweets")
            }
            List(viewModel.tweets, id: \.id) { tweet in
                TweetView(tweet)
            }
                .navigationBarTitle("Tweets")
                .onAppear(perform: { self.viewModel.startStream() })
                .listStyle(.plain)
                .animation(.default, value: viewModel.tweets)
        }
    }
}

struct TweetView: View {
    @State private var tweet: Tweet
    
    init(_ tweet: Tweet) {
        self.tweet = tweet
    }
    
    var body: some View {
        Text(tweet.text)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        TweetListView()
    }
}

