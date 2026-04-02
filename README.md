# TeleFeed

Telega is a native macOS menu bar watcher for public Telegram channels. It uses Swift, SwiftUI, AppKit, and the TDLib JSON interface to deliver a read-only, notification-first workflow for unread channel posts.

## Overview

- Menu bar only macOS app with `LSUIElement`, background behavior after closing the window, and launch-at-login support.
- Read-only Telegram integration focused on public channels.
- QR / trusted-device login through TDLib, with 2FA password step when Telegram requires it.
- One macOS notification per new post in watched channels.
- Clicking a notification opens Telega directly to the unread list of the corresponding channel.
- Unread posts are loaded on demand from the Telegram account read state, capped to the latest unread items per watched channel.
- Text, photo, and video posts are shown inside the app.
- Reader mode uses a native macOS pipeline built from AppKit, `WKWebView`, Mozilla Readability, and a custom article HTML template.
- Reader extraction prefers Readability first, falls back to a legacy parser when needed, and can still open the source article in Safari.
- No intentional permanent message history archive and no intentional permanent media library.

## Architecture

The codebase follows MVVM with a service layer and is split into feature/service folders:

- `Sources/App`: menu bar shell, AppKit window lifecycle, routing, settings, root composition.
- `Sources/Auth`: QR/password authorization UI and state.
- `Sources/Channels`: watched channel management and selection.
- `Sources/Feed`: unread list fetching and presentation.
- `Sources/Viewer`: detail viewer for text/photo/video posts.
- `Sources/Reader`: article reader orchestration, Readability extraction, HTML template generation, and the `WKWebView` renderer.
- `Sources/Services/TelegramService`: TDLib bridge, JSON request/response handling, auth flow, media download coordination.
- `Sources/Services/ReaderService`: article loading, fallback extraction pipeline, and source metadata normalization.
- `Sources/Services/NotificationService`: macOS local notifications and click routing.
- `Sources/Services/SecureStorage`: Keychain-backed secrets storage.
- `Sources/Services/StateStore`: persisted app state for watched channels, notification markers, and app settings.
- `Sources/Shared`: shared models and localization helpers.

## Build

### Requirements

- macOS 15 or newer
- Xcode 26.4 or newer
- `xcodegen` installed

### Generate the project

```bash
xcodegen generate
```

### Build from Terminal

```bash
xcodebuild -project Telega.xcodeproj -scheme Telega -configuration Debug -destination platform=macOS build
```

### Open in Xcode

```bash
open Telega.xcodeproj
```

## Telegram Credentials Setup

Telega does not hardcode `api_id` or `api_hash`.

1. Open [my.telegram.org](https://my.telegram.org).
2. Create an application and copy your `api_id` and `api_hash`.
3. Launch Telega.
4. Paste the credentials into the authorization/settings UI.
5. Telega stores them in the macOS Keychain.

## TDLib Setup

This project uses the official TDLib JSON interface through the `TDLibFramework` Swift package dependency, which ships TDLib as an XCFramework for macOS.

Default integration path:

1. Run `xcodegen generate`.
2. Build the app; Xcode/SPM resolves `TDLibFramework` automatically.
3. No separate manual TDLib compilation is required for the default project setup.

What the app configures in TDLib:

- Persistent state directory in `~/Library/Application Support/Telega/TDLibState`
- Temporary media cache in `~/Library/Caches/Telega/TDLibTempMedia`
- `use_message_database = false`
- `use_file_database = false`
- `use_chat_info_database = false`
- `use_secret_chats = false`

This keeps TDLib focused on auth/session continuity and live fetching instead of building a productized local archive.

## Runtime Flow

1. Enter `api_id` and `api_hash`.
2. Telega initializes TDLib and requests QR authentication.
3. Scan the QR code with a trusted Telegram device.
4. If Telegram asks for the 2FA password, enter it in the app.
5. Add public channels by username or `t.me` link.
6. Watched channels stay open in TDLib so new posts and chat read-state updates continue to arrive.
7. Unread posts are derived from Telegram's `last_read_inbox_message_id` / `unread_count` state for the signed-in account.
8. Opening a post in Telega marks it as viewed/read through TDLib for that Telegram account.
9. Reader mode fetches the article, extracts readable content with Mozilla Readability, renders the result through a custom macOS HTML template in `WKWebView`, and falls back to Safari when requested.

## Storage Policy

Persisted intentionally:

- Telegram auth/session state
- watched channels list
- channel identifiers and usernames
- latest known unread counters / read markers needed to restore UI quickly
- last notified message ID per watched channel to avoid duplicate local notifications
- launch-at-login setting
- Telegram credentials and TDLib encryption key in Keychain

Not intentionally persisted as product features:

- full message history
- permanent media library
- long-term local message archive UI

Temporary cache:

- photo/video payloads may be downloaded temporarily to the app cache directory for in-app viewing
- the cache is cleaned on startup and logout

## Known Limitations

- Public channels only; groups, private chats, replies, and sending are intentionally unsupported.
- Unsupported Telegram post types can still appear in unread results, but only text/photo/video rendering is implemented.
- QR login is the primary path; there is no full fallback phone-code UI.
- TDLib still owns the session/auth internals required for reconnect and restore.
- Temporary media files may remain in cache until next launch/logout if the app is interrupted unexpectedly.

## Reader Notes

- Reader mode is intentionally macOS-native and does not depend on UIKit.
- The renderer is separate from extraction, so the app can keep a predictable UI even when the source site markup is messy.
- Translation is applied before rendering so the same article pipeline supports original and translated views.
- The HTML template is controlled in-app, which makes typography and spacing consistent with the app's own settings.
