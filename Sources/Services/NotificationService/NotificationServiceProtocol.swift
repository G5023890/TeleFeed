import Foundation

struct NotificationRoute: Equatable {
    let chatID: Int64
}

@MainActor
protocol NotificationServiceProtocol: AnyObject {
    var onOpenChannel: ((NotificationRoute) -> Void)? { get set }
    func requestAuthorization() async
    func postNotification(for post: UnreadPost) async
    func removeNotification(chatID: Int64, messageID: Int64)
}
