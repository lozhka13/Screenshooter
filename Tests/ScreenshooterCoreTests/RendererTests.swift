import AppKit
import Testing

@testable import ScreenshooterCore

struct RendererTests {
  // Black and white stripes, so a blur visibly changes pixels.
  func stripes() -> CGImage {
    let context = CGContext(
      data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in stride(from: 0, to: 400, by: 4) {
      context.setFillColor(x % 8 == 0 ? NSColor.black.cgColor : NSColor.white.cgColor)
      context.fill(CGRect(x: x, y: 0, width: 4, height: 200))
    }
    return context.makeImage()!
  }

  func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    let data = image.dataProvider!.data! as Data
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<offset + 3])
  }

  @Test func blurChangesOnlyItsArea() throws {
    let source = stripes()
    let result = try #require(Renderer.render(source, marks: [Mark(blur: CGRect(x: 0, y: 0, width: 0.5, height: 1))]))
    #expect(result.width == source.width && result.height == source.height)
    // Inside the blurred left half neighbouring stripes become the same colour…
    #expect(pixel(result, 40, 100) == pixel(result, 44, 100))
    // …the right half is untouched.
    #expect(pixel(result, 300, 100) != pixel(result, 304, 100))
  }

  @Test func boxIsDrawnInRed() throws {
    let result = try #require(Renderer.render(stripes(), marks: [Mark(tool: .box, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.9, y: 0.9))]))
    let edge = pixel(result, 40, 100)  // left side of the box
    #expect(edge[0] > 200 && edge[1] < 120)
  }
}

struct BeautifyTests {
  @Test func addsPaddingAndKeepsTheShot() throws {
    let context = CGContext(
      data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
    let result = try #require(Renderer.beautify(context.makeImage()!))
    #expect(result.width == 228 && result.height == 128)  // 7 % of the long edge on each side
    let data = result.dataProvider!.data! as Data
    let center = (64 * result.bytesPerRow) + 114 * 4
    #expect(data[center] > 240 && data[center + 2] > 240)  // the white screenshot in the middle
    #expect(data[2] > 150)  // a blue-violet corner
  }
}
