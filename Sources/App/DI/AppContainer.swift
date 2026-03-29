import Foundation

@MainActor
final class AppContainer {
    let secureStorage: SecureStorageProtocol
    let stateStore: StateStoreProtocol
    let notificationService: NotificationServiceProtocol
    let telegramService: TelegramServiceProtocol
    let rssService: RSSServiceProtocol
    let readerService: ReaderServiceProtocol
    let translationService: TranslationServiceProtocol
    let mainViewModel: MainViewModel

    init() {
        let secureStorage = KeychainSecureStorage()
        let stateStore = FileAppStateStore()
        let notificationService = LocalNotificationService()
        let telegramService = TelegramService(secureStorage: secureStorage)
        let rssService = RSSService()
        let readerService = ReaderService()
        let translationService = TranslationService()

        self.secureStorage = secureStorage
        self.stateStore = stateStore
        self.notificationService = notificationService
        self.telegramService = telegramService
        self.rssService = rssService
        self.readerService = readerService
        self.translationService = translationService
        self.mainViewModel = MainViewModel(
            stateStore: stateStore,
            telegramService: telegramService,
            rssService: rssService,
            notificationService: notificationService,
            readerService: readerService,
            translationService: translationService
        )
    }
}
