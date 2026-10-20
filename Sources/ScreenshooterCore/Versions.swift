import Foundation

public enum Versions {
  // "2.10.0" is newer than "2.9.1"; a leading "v" is ignored.
  public static func isNewer(_ candidate: String, than current: String) -> Bool {
    let parse = { (version: String) in
      version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
    }
    let a = parse(candidate)
    let b = parse(current)
    for index in 0..<max(a.count, b.count) {
      let x = index < a.count ? a[index] : 0
      let y = index < b.count ? b[index] : 0
      if x != y { return x > y }
    }
    return false
  }
}
