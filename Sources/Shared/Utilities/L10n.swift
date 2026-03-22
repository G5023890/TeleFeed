import Foundation

enum L10n {
    private static let fallbackStrings: [String: [String: String]] = [
        "en": [
            "app.title": "Telega",
            "menu.open": "Open Feed",
            "menu.settings": "Settings...",
            "menu.quit": "Quit Telega",
            "sidebar.close": "Close Open Feed",
            "state.offline": "Offline",
            "state.connecting": "Connecting",
            "state.updating": "Updating",
            "state.ready": "Connected",
            "state.waitingNetwork": "Waiting for network",
            "sidebar.channels": "Watched Channels",
            "sidebar.addChannel": "Add",
            "sidebar.channelPlaceholder": "@channel or https://t.me/channel",
            "sidebar.empty": "Add a public Telegram channel to start watching posts.",
            "sidebar.remove": "Remove",
            "sidebar.unreadCount": "%lld unread",
            "feed.title": "Unread Posts",
            "feed.empty": "No unread posts right now.",
            "feed.refresh": "Refresh",
            "feed.openViewer": "Open",
            "feed.unsupported": "Unsupported post type",
            "viewer.close": "Close",
            "viewer.loadingMedia": "Loading media...",
            "viewer.mediaUnavailable": "Media is unavailable.",
            "general.close": "Close",
            "auth.title": "Telegram Access",
            "auth.credentialsTitle": "API Credentials",
            "auth.apiId": "API ID",
            "auth.apiHash": "API Hash",
            "auth.saveCredentials": "Save Credentials",
            "auth.qrTitle": "QR Login",
            "auth.generateQR": "Generate QR",
            "auth.regenerateQR": "Refresh QR",
            "auth.trustedDevice": "Scan the QR code with a trusted Telegram device.",
            "auth.passwordTitle": "Two-Step Verification",
            "auth.passwordPlaceholder": "Telegram password",
            "auth.submitPassword": "Unlock",
            "auth.authorized": "Telegram session is active.",
            "auth.loggingIn": "Preparing Telegram session...",
            "auth.waiting": "Waiting for Telegram authorization...",
            "auth.notLoggedIn": "You are not logged in yet.",
            "auth.currentState": "Current state: %@",
            "auth.retryLogin": "Restart Login",
            "auth.error": "Telegram error",
            "settings.title": "Settings",
            "settings.launchAtLogin": "Launch at login",
            "settings.logout": "Log Out",
            "settings.close": "Done",
            "settings.storageNote": "Message history and media are not intentionally stored permanently.",
            "channels.addError": "Unable to add channel.",
            "channels.duplicate": "This channel is already watched.",
            "channels.invalid": "Only public channel usernames or links are supported.",
            "notifications.newPostTitle": "New post in %@",
            "notifications.defaultBody": "Open unread posts in Telega.",
            "general.cancel": "Cancel",
            "general.remove": "Remove",
            "general.save": "Save",
            "general.retry": "Retry"
        ],
        "ru": [
            "app.title": "Telega",
            "menu.open": "Открыть ленту",
            "menu.settings": "Настройки...",
            "menu.quit": "Выйти из Telega",
            "sidebar.close": "Закрыть Open Feed",
            "state.offline": "Офлайн",
            "state.connecting": "Подключение",
            "state.updating": "Обновление",
            "state.ready": "Подключено",
            "state.waitingNetwork": "Ожидание сети",
            "sidebar.channels": "Отслеживаемые каналы",
            "sidebar.addChannel": "Добавить",
            "sidebar.channelPlaceholder": "@channel или https://t.me/channel",
            "sidebar.empty": "Добавьте публичный Telegram-канал, чтобы отслеживать новые посты.",
            "sidebar.remove": "Удалить",
            "sidebar.unreadCount": "%lld непрочитанных",
            "feed.title": "Непрочитанные посты",
            "feed.empty": "Сейчас непрочитанных постов нет.",
            "feed.refresh": "Обновить",
            "feed.openViewer": "Открыть",
            "feed.unsupported": "Неподдерживаемый тип поста",
            "viewer.close": "Закрыть",
            "viewer.loadingMedia": "Загрузка медиа...",
            "viewer.mediaUnavailable": "Медиа недоступно.",
            "general.close": "Закрыть",
            "auth.title": "Доступ к Telegram",
            "auth.credentialsTitle": "Данные Telegram API",
            "auth.apiId": "API ID",
            "auth.apiHash": "API Hash",
            "auth.saveCredentials": "Сохранить данные",
            "auth.qrTitle": "Вход по QR",
            "auth.generateQR": "Показать QR",
            "auth.regenerateQR": "Обновить QR",
            "auth.trustedDevice": "Сканируйте QR-код доверенным устройством с Telegram.",
            "auth.passwordTitle": "Двухэтапная проверка",
            "auth.passwordPlaceholder": "Пароль Telegram",
            "auth.submitPassword": "Разблокировать",
            "auth.authorized": "Сессия Telegram активна.",
            "auth.loggingIn": "Подготавливаю сессию Telegram...",
            "auth.waiting": "Ожидание авторизации Telegram...",
            "auth.notLoggedIn": "Вы еще не вошли в Telegram.",
            "auth.currentState": "Текущее состояние: %@",
            "auth.retryLogin": "Перезапустить вход",
            "auth.error": "Ошибка Telegram",
            "settings.title": "Настройки",
            "settings.launchAtLogin": "Запускать при входе",
            "settings.logout": "Выйти из аккаунта",
            "settings.close": "Готово",
            "settings.storageNote": "История сообщений и медиа не сохраняются намеренно на постоянной основе.",
            "channels.addError": "Не удалось добавить канал.",
            "channels.duplicate": "Этот канал уже отслеживается.",
            "channels.invalid": "Поддерживаются только публичные каналы по username или ссылке.",
            "notifications.newPostTitle": "Новый пост в %@",
            "notifications.defaultBody": "Откройте непрочитанные посты в Telega.",
            "general.cancel": "Отмена",
            "general.remove": "Удалить",
            "general.save": "Сохранить",
            "general.retry": "Повторить"
        ]
    ]

    private static let preferredLanguageCode: String = {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
    }()

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = fallbackStrings[preferredLanguageCode]?[key]
            ?? fallbackStrings["en"]?[key]
            ?? key

        guard arguments.isEmpty == false else {
            return format
        }

        var rendered = format
        for argument in arguments {
            if rendered.contains("%lld") {
                rendered = rendered.replacingOccurrences(of: "%lld", with: String(describing: argument), options: [], range: rendered.range(of: "%lld"))
                continue
            }

            if rendered.contains("%@") {
                rendered = rendered.replacingOccurrences(of: "%@", with: String(describing: argument), options: [], range: rendered.range(of: "%@"))
            }
        }
        return rendered
    }
}
