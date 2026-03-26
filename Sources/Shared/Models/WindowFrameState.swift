import Foundation

struct WindowFrameState: Codable, Hashable {
    var originX: Double
    var originY: Double
    var width: Double
    var height: Double

    init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.originX = Double(rect.origin.x)
        self.originY = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }

    var rect: CGRect {
        CGRect(x: originX, y: originY, width: width, height: height)
    }
}
