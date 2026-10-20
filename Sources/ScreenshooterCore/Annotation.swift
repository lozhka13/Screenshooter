// Marks drawn on a screenshot — arrows, boxes, text, blur — and rendering them into the image.
import AppKit
import CoreImage

public enum Tool: String, CaseIterable, Sendable {
  case arrow, box, text, blur

  public var symbol: String {
    switch self {
    case .arrow: "arrow.up.right"
    case .box: "rectangle"
    case .text: "textformat"
    case .blur: "eye.slash"
    }
  }

  public var key: String {
    switch self {
    case .arrow: "A"
    case .box: "B"
    case .text: "T"
    case .blur: "P"
    }
  }
}

public struct Mark: Identifiable, Sendable {
  public let id = UUID()
  public var tool: Tool
  public var start: CGPoint  // normalized, origin at the top left
  public var end: CGPoint
  public var text = ""

  public init(tool: Tool, start: CGPoint, end: CGPoint, text: String = "") {
    self.tool = tool
    self.start = start
    self.end = end
    self.text = text
  }

  public init(blur rect: CGRect) {
    self.init(tool: .blur, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY))
  }

  public var rect: CGRect {
    CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
  }
}

public let markColor = NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)

public enum Renderer {
  // Draws the marks onto a full-size copy of the image.
  public static func render(_ image: CGImage, marks: [Mark]) -> CGImage? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let full = CGRect(x: 0, y: 0, width: width, height: height)
    context.draw(image, in: full)

    // Normalized top-left → pixels with a bottom-left origin.
    func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * width, y: (1 - p.y) * height) }
    func rect(_ r: CGRect) -> CGRect {
      CGRect(x: r.minX * width, y: (1 - r.maxY) * height, width: r.width * width, height: r.height * height)
    }
    let line = max(4, width * 0.0035)

    // Blur first so arrows and text stay sharp on top.
    let source = CIImage(cgImage: image)
    let ciContext = CIContext()
    for mark in marks where mark.tool == .blur {
      let area = rect(mark.rect).integral.intersection(full)
      guard area.width > 1, area.height > 1 else { continue }
      let pixelated = source.cropped(to: area)
        .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(12, area.height / 2), kCIInputCenterKey: CIVector(cgPoint: area.origin)])
        .cropped(to: area)
      if let tile = ciContext.createCGImage(pixelated, from: area) { context.draw(tile, in: area) }
    }

    context.setStrokeColor(markColor.cgColor)
    context.setFillColor(markColor.cgColor)
    context.setLineWidth(line)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    for mark in marks {
      switch mark.tool {
      case .box:
        context.addPath(CGPath(roundedRect: rect(mark.rect), cornerWidth: line * 2, cornerHeight: line * 2, transform: nil))
        context.strokePath()
      case .arrow:
        let from = point(mark.start)
        let to = point(mark.end)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = line * 4.5
        let base = CGPoint(x: to.x - cos(angle) * head * 0.8, y: to.y - sin(angle) * head * 0.8)
        context.move(to: from)
        context.addLine(to: base)
        context.strokePath()
        context.move(to: to)
        context.addLine(to: CGPoint(x: to.x - head * cos(angle - .pi / 7), y: to.y - head * sin(angle - .pi / 7)))
        context.addLine(to: CGPoint(x: to.x - head * cos(angle + .pi / 7), y: to.y - head * sin(angle + .pi / 7)))
        context.closePath()
        context.fillPath()
      case .text:
        drawText(mark.text, at: point(mark.start), size: width * 0.016, in: context)
      case .blur:
        break
      }
    }
    return context.makeImage()
  }

  // White text on a red pill, top-left corner at `topLeft`.
  static func drawText(_ text: String, at topLeft: CGPoint, size: CGFloat, in context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.white,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let textSize = string.size()
    let padding = size * 0.4
    let box = CGRect(
      x: topLeft.x, y: topLeft.y - textSize.height - padding * 2, width: textSize.width + padding * 2,
      height: textSize.height + padding * 2)
    context.addPath(CGPath(roundedRect: box, cornerWidth: padding * 1.5, cornerHeight: padding * 1.5, transform: nil))
    context.setFillColor(markColor.cgColor)
    context.fillPath()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    string.draw(at: CGPoint(x: box.minX + padding, y: box.minY + padding))
    NSGraphicsContext.restoreGraphicsState()
  }
}

extension Renderer {
  // A presentation-ready copy: the screenshot with rounded corners and a soft shadow
  // on a gradient background, like the app's icon.
  public static func beautify(_ image: CGImage) -> CGImage? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let padding = (max(width, height) * 0.07).rounded()
    let canvas = CGSize(width: width + padding * 2, height: height + padding * 2)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let gradient = CGGradient(
        colorsSpace: space,
        colors: [
          NSColor(red: 0.43, green: 0.29, blue: 1, alpha: 1).cgColor,
          NSColor(red: 0.23, green: 0.42, blue: 1, alpha: 1).cgColor,
          NSColor(red: 0.09, green: 0.78, blue: 0.94, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.55, 1])
    else { return nil }
    context.drawLinearGradient(
      gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])

    let frame = CGRect(x: padding, y: padding, width: width, height: height)
    let radius = min(width, height) * 0.025
    let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -padding * 0.12), blur: padding * 0.45,
      color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.clip()
    context.draw(image, in: frame)
    return context.makeImage()
  }
}
