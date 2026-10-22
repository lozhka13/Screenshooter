// A clear button at the end of a text field, shown while it has text.
import SwiftUI

extension View {
  func clearable(_ text: Binding<String>) -> some View { modifier(Clearable(text: text)) }
}

struct Clearable: ViewModifier {
  @Binding var text: String

  func body(content: Content) -> some View {
    HStack(spacing: 4) {
      content
      if !text.isEmpty {
        Button { text = "" } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(L("Clear"))
      }
    }
  }
}
