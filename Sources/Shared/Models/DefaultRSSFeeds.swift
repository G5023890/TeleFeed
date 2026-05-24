import Foundation

enum DefaultRSSFeeds {
    static let feeds: [RSSFeedSource] = [
        RSSFeedSource(
            urlString: "https://lifehacker.ru/feed/",
            title: "Lifehacker",
            lastItemIdentifier: nil
        ),
        RSSFeedSource(
            urlString: "https://habr.com/ru/rss/flows/popsci/articles/?fl=ru",
            title: "Habr: Научпоп",
            lastItemIdentifier: nil
        ),
        RSSFeedSource(
            urlString: "https://www.techcult.ru/rss",
            title: "TechCult",
            lastItemIdentifier: nil
        ),
        RSSFeedSource(
            urlString: "https://www.newsru.co.il/il/www/news/all",
            title: "NEWSru.co.il",
            lastItemIdentifier: nil
        ),
        RSSFeedSource(
            urlString: "https://www.iphones.ru/feed",
            title: "iPhones.ru",
            lastItemIdentifier: nil
        ),
        RSSFeedSource(
            urlString: "https://appleinsider.ru/rss/",
            title: "AppleInsider.ru",
            lastItemIdentifier: nil
        ),
        RSSFeedSource(
            urlString: "https://appleinsider.com/rss/news",
            title: "AppleInsider",
            lastItemIdentifier: nil
        ),
    ]
}
