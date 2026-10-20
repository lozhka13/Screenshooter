// Live preview of marks while editing; the marks and the renderer live in ScreenshooterCore.
import ScreenshooterCore
import SwiftUI

// Live preview of the marks over the image while editing.
struct MarksOverlay: View {
  let marks: [Mark]
  let size: CGSize
  let image: NSImage

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(marks) { mark in
        switch mark.tool {
        case .blur:
          let r = scaled(mark.rect)
          Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .blur(radius: 14)
            .mask(alignment: .topLeading) {
              Rectangle().frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
            }
        case .box:
          let r = scaled(mark.rect)
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(markColor), lineWidth: 3)
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
        case .arrow:
          ArrowShape(from: scaled(mark.start), to: scaled(mark.end))
            .fill(Color(markColor))
        case .text:
          Text(mark.text)
            .font(.system(size: max(11, size.width * 0.016), weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(markColor), in: RoundedRectangle(cornerRadius: 6))
            .offset(x: scaled(mark.start).x, y: scaled(mark.start).y)
        }
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .allowsHitTesting(false)
  }

  func scaled(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
  func scaled(_ r: CGRect) -> CGRect {
    CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
  }
}

struct ArrowShape: Shape {
  let from: CGPoint
  let to: CGPoint

  func path(in rect: CGRect) -> Path {
    let angle = atan2(to.y - from.y, to.x - from.x)
    let head: CGFloat = 16
    let width: CGFloat = 3
    let base = CGPoint(x: to.x - cos(angle) * head * 0.8, y: to.y - sin(angle) * head * 0.8)
    var path = Path()
    path.addPath(
      Path { line in
        line.move(to: from)
        line.addLine(to: base)
      }.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round)))
    path.move(to: to)
    path.addLine(to: CGPoint(x: to.x - head * cos(angle - .pi / 7), y: to.y - head * sin(angle - .pi / 7)))
    path.addLine(to: CGPoint(x: to.x - head * cos(angle + .pi / 7), y: to.y - head * sin(angle + .pi / 7)))
    path.closeSubpath()
    return path
  }
}
