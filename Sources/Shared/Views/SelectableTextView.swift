import AppKit
import SwiftUI

struct SelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let lineSpacing: CGFloat
    let maximumWidth: CGFloat?

    init(
        text: String,
        font: NSFont,
        textColor: NSColor = .labelColor,
        lineSpacing: CGFloat = 0,
        maximumWidth: CGFloat? = nil
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.lineSpacing = lineSpacing
        self.maximumWidth = maximumWidth
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        context.coordinator.apply(self, to: textView)
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        context.coordinator.apply(self, to: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = maximumWidth ?? proposal.width ?? 760
        guard width.isFinite, width > 0 else {
            return nil
        }

        return context.coordinator.sizeThatFits(width: width, view: self)
    }

    final class Coordinator {
        private var cachedText: String = ""
        private var cachedFont: NSFont = .systemFont(ofSize: 13)
        private var cachedTextColor: NSColor = .labelColor
        private var cachedLineSpacing: CGFloat = 0
        private var cachedAttributedString: NSAttributedString = NSAttributedString(string: "")
        private var cachedMeasurementWidth: CGFloat?
        private var cachedMeasurementHeight: CGFloat?

        func apply(_ view: SelectableTextView, to textView: NSTextView) {
            let textNeedsUpdate = cachedText != view.text
            let fontNeedsUpdate = !cachedFont.isEqual(view.font)
            let colorNeedsUpdate = !cachedTextColor.isEqual(view.textColor)
            let spacingNeedsUpdate = cachedLineSpacing != view.lineSpacing

            if textNeedsUpdate || fontNeedsUpdate || colorNeedsUpdate || spacingNeedsUpdate {
                cachedText = view.text
                cachedFont = view.font
                cachedTextColor = view.textColor
                cachedLineSpacing = view.lineSpacing
                cachedAttributedString = Self.makeAttributedString(
                    text: view.text,
                    font: view.font,
                    textColor: view.textColor,
                    lineSpacing: view.lineSpacing
                )
                cachedMeasurementWidth = nil
                cachedMeasurementHeight = nil
            }

            let containerWidth = view.maximumWidth ?? CGFloat.greatestFiniteMagnitude
            textView.textContainer?.containerSize = CGSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)

            guard textView.string != view.text || textNeedsUpdate || fontNeedsUpdate || colorNeedsUpdate || spacingNeedsUpdate else {
                return
            }

            textView.textStorage?.setAttributedString(cachedAttributedString)
        }

        func sizeThatFits(width: CGFloat, view: SelectableTextView) -> CGSize {
            if cachedMeasurementWidth == width, let cachedMeasurementHeight {
                return CGSize(width: width, height: cachedMeasurementHeight)
            }

            let attributedString = attributedString(for: view)
            let rect = attributedString.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let height = ceil(rect.height)
            cachedMeasurementWidth = width
            cachedMeasurementHeight = height
            return CGSize(width: width, height: height)
        }

        private func attributedString(for view: SelectableTextView) -> NSAttributedString {
            if cachedText != view.text || !cachedFont.isEqual(view.font) || !cachedTextColor.isEqual(view.textColor) || cachedLineSpacing != view.lineSpacing {
                cachedText = view.text
                cachedFont = view.font
                cachedTextColor = view.textColor
                cachedLineSpacing = view.lineSpacing
                cachedAttributedString = Self.makeAttributedString(
                    text: view.text,
                    font: view.font,
                    textColor: view.textColor,
                    lineSpacing: view.lineSpacing
                )
                cachedMeasurementWidth = nil
                cachedMeasurementHeight = nil
            }

            return cachedAttributedString
        }

        private static func makeAttributedString(
            text: String,
            font: NSFont,
            textColor: NSColor,
            lineSpacing: CGFloat
        ) -> NSAttributedString {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = lineSpacing
            paragraphStyle.lineBreakMode = .byWordWrapping

            return NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
        }
    }
}

struct VerticalStoryMotion<ID: Hashable>: ViewModifier {
    let id: ID
    var duration: Double = 0.28
    var travel: CGFloat = 20

    @State private var phase: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .offset(y: -travel * (1 - phase))
            .opacity(0.74 + (0.26 * phase))
            .scaleEffect(0.992 + (0.008 * phase), anchor: .top)
            .blur(radius: 6 * (1 - phase))
            .compositingGroup()
            .onAppear {
                phase = 1
            }
            .onChange(of: id) { _, _ in
                phase = 0
                withAnimation(.snappy(duration: duration)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func verticalStoryMotion<ID: Hashable>(
        id: ID,
        duration: Double = 0.28,
        travel: CGFloat = 20
    ) -> some View {
        modifier(VerticalStoryMotion(id: id, duration: duration, travel: travel))
    }
}
