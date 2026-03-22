import Foundation

@MainActor
final class AppContainer {
    let secureStorage: SecureStorageProtocol
    let stateStore: StateStoreProtocol
    let notificationService: NotificationServiceProtocol
    let telegramService: TelegramServiceProtocol
    let mainViewModel: MainViewModel

    init() {
        let secureStorage = KeychainSecureStorage()
        let stateStore = FileAppStateStore()
        let notificationService = LocalNotificationService()
        let telegramService = TelegramService(secureStorage: secureStorage)

        self.secureStorage = secureStorage
        self.stateStore = stateStore
        self.notificationService = notificationService
        self.telegramService = telegramService
        self.mainViewModel = MainViewModel(
            stateStore: stateStore,
            telegramService: telegramService,
            notificationService: notificationService
        )
    }
}

