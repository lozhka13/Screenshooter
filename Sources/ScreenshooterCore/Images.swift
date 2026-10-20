// Loading screenshots and video frames as CGImage, and encoding them.
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageError: LocalizedError {
  case unreadable(String)
  case unencodable

  public var errorDescription: String? {
    switch self {
    case .unreadable(let name): "Can't read image: \(name)"
    case .unencodable: "Can't encode image"
    }
  }
}

public enum Images {
  // Full size, or scaled so the long edge fits `maxSize`; a video gives its first frame.
  public static func load(_ url: URL, maxSize: Int? = nil) async throws -> CGImage {
    if isVideo(url) {
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
      generator.appliesPreferredTrackTransform = true
      if let maxSize { generator.maximumSize = CGSize(width: maxSize, height: maxSize) }
      return try await generator.image(at: .zero).image
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw ImageError.unreadable(url.lastPathComponent)
    }
    let image: CGImage?
    if let maxSize {
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxSize,
      ]
      image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    } else {
      image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    guard let image else { throw ImageError.unreadable(url.lastPathComponent) }
    return image
  }

  public static func encode(_ image: CGImage, as type: UTType, quality: Double = 0.85) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
      throw ImageError.unencodable
    }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ImageError.unencodable }
    return data as Data
  }

  // Same format as the original file: PNG stays PNG, everything else becomes JPEG.
  public static func write(_ image: CGImage, to url: URL) throws {
    let type: UTType = url.pathExtension.lowercased() == "png" ? .png : .jpeg
    try encode(image, as: type, quality: 0.92).write(to: url, options: .atomic)
  }
}
