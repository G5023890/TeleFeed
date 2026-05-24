import SwiftUI

struct IOSGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var colors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.05, green: 0.06, blue: 0.08),
                Color(red: 0.10, green: 0.11, blue: 0.13),
                Color(red: 0.03, green: 0.04, blue: 0.05),
            ]
        }

        return [
            Color(red: 0.96, green: 0.97, blue: 0.98),
            Color(red: 0.91, green: 0.95, blue: 0.97),
            Color(red: 0.98, green: 0.95, blue: 0.91),
        ]
    }
}

extension UnreadPost {
    var previewBody: String {
        let title = titleOrFallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard summary.localizedCaseInsensitiveCompare(title) != .orderedSame else {
            return ""
        }
        return summary
    }
}
