import Foundation

struct ReaderArticle: Hashable, Identifiable {
    enum Block: Hashable {
        case heading(String, level: Int)
        case paragraph(String)
        case quote(String)
        case list(items: [String], ordered: Bool)
        case code(String)
        case separator
    }

    let sourceURL: URL
    let canonicalURL: URL
    let title: String
    let body: String
    let renderHTML: String
    let blocks: [Block]
    let excerpt: String?
    let imageURL: URL?

    var id: URL { canonicalURL }
}
