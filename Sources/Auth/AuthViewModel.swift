import AppKit
import CoreImage.CIFilterBuiltins
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var apiID = ""
    @Published var apiHash = ""
    @Published var password = ""
    @Published var state: TelegramAuthState = .missingCredentials
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var debugMessage = ""

    private let context = CIContext()

    var qrLink: String? {
        guard case .waitingForQRCode(let link) = state else {
            return nil
        }
        return link
    }

    var passwordHint: String {
        guard case .waitingPassword(let hint) = state else {
            return ""
        }
        return hint
    }

    var stateDebugLabel: String {
        switch state {
        case .missingCredentials:
            return "missingCredentials"
        case .initializing:
            return "initializing"
        case .waitingPhoneNumber:
            return "waitingPhoneNumber"
        case .waitingForQRCode:
            return "waitingForQRCode"
        case .waitingPassword:
            return "waitingPassword"
        case .ready:
            return "ready"
        case .loggingOut:
            return "loggingOut"
        case .closed:
            return "closed"
        case .failed:
            return "failed"
        }
    }

    var hasDebugMessage: Bool {
        debugMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var qrImage: NSImage? {
        guard let qrLink else {
            return nil
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(qrLink.utf8)
        filter.correctionLevel = "Q"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 240, height: 240))
    }
}
