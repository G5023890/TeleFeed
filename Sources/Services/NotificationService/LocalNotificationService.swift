import Foundation
import UserNotifications

@MainActor
final class LocalNotificationService: NSObject, NotificationServiceProtocol {
    var onOpenChannel: ((NotificationRoute) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func postNotification(for post: UnreadPost) async {
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("notifications.newPostTitle", post.channelTitle)
        content.body = post.summary.isEmpty ? L10n.tr("notifications.defaultBody") : post.summary
        content.sound = .default
        content.userInfo = [
            "chatID": post.chatID,
            "messageID": post.messageID,
        ]

        let identifier = notificationIdentifier(chatID: post.chatID, messageID: post.messageID)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    func removeNotification(chatID: Int64, messageID: Int64) {
        let identifier = notificationIdentifier(chatID: chatID, messageID: messageID)
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func notificationIdentifier(chatID: Int64, messageID: Int64) -> String {
        "chat-\(chatID)-message-\(messageID)"
    }
}

extension LocalNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let chatID = userInfo["chatID"] as? Int64 else {
            return
        }

        await MainActor.run {
            self.onOpenChannel?(NotificationRoute(chatID: chatID))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
