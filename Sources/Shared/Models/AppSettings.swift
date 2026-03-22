import Foundation

struct AppSettings: Codable, Equatable {
    var launchAtLoginEnabled: Bool = true
}

struct TelegramCredentials: Equatable {
    let apiID: Int32
    let apiHash: String
}

