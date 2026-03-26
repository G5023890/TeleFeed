import SwiftUI

enum AppTheme {
    static func windowGradientColors(for scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.10, green: 0.11, blue: 0.13),
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color(red: 0.07, green: 0.08, blue: 0.10),
            ]
        }

        return [
            Color(red: 0.97, green: 0.95, blue: 0.92),
            Color(red: 0.94, green: 0.92, blue: 0.89),
            Color(red: 0.92, green: 0.90, blue: 0.87),
        ]
    }

    static func topGlowColor(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color(red: 0.22, green: 0.26, blue: 0.32).opacity(0.18)
        }

        return Color.white.opacity(0.72)
    }

    static func bottomGlowColor(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color(red: 0.18, green: 0.15, blue: 0.12).opacity(0.14)
        }

        return Color(red: 0.98, green: 0.90, blue: 0.80).opacity(0.52)
    }

    static func toolbarPillFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    static func toolbarPillStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    static func drawerFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.72)
    }

    static func drawerStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82)
    }

    static func drawerShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.55) : Color.black.opacity(0.12)
    }

    static func surfaceFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.88)
    }

    static func surfaceStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    static func inputFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.88)
    }

    static func chipFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.88)
    }

    static func chipStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05)
    }

    static func rowFill(for scheme: ColorScheme, selected: Bool, unread: Bool) -> Color {
        if scheme == .dark {
            if selected {
                return Color.white.opacity(0.11)
            }

            return unread ? Color.white.opacity(0.05) : Color.white.opacity(0.02)
        }

        return selected
            ? Color(red: 0.88, green: 0.86, blue: 0.82)
            : (unread ? Color.white.opacity(0.40) : Color.clear)
    }

    static func rowStroke(for scheme: ColorScheme, selected: Bool, unread: Bool) -> Color {
        if scheme == .dark {
            if selected {
                return Color.white.opacity(0.14)
            }

            return unread ? Color.white.opacity(0.10) : Color.white.opacity(0.05)
        }

        return selected ? Color.black.opacity(0.06) : (unread ? Color.black.opacity(0.05) : Color.clear)
    }

    static func rowShadow(for scheme: ColorScheme, selected: Bool, unread: Bool) -> Color {
        if selected {
            return scheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.04)
        }

        if unread {
            return scheme == .dark ? Color.black.opacity(0.24) : Color.black.opacity(0.03)
        }

        return .clear
    }

    static func viewerFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.28)
    }

    static func readerChipFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.88)
    }

    static func readerChipStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    static func separatorColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}
