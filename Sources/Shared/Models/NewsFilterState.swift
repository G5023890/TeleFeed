import Foundation

enum NewsSourceFilter: String, Codable, CaseIterable, Identifiable {
    case all
    case rss
    case telegram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "Все"
        case .rss:
            return "RSS"
        case .telegram:
            return "Telegram"
        }
    }
}

struct DraftNewsFilterState: Equatable {
    var query: String = ""
    var source: NewsSourceFilter = .all
}

struct AppliedNewsFilterState: Equatable, Hashable, Codable {
    var query: String
    var source: NewsSourceFilter

    init(query: String = "", source: NewsSourceFilter = .all) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
    }

    init(draft: DraftNewsFilterState) {
        self.init(query: draft.query, source: draft.source)
    }
}
