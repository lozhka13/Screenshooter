// The window content: preview with loupe, glass buttons.
import SwiftUI

struct KeyCap: View {
  let key: String

  var body: some View {
    Text(key)
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
  }
}

struct SorterView: View {
  @ObservedObject var model: SorterModel
  @Namespace private var glass
  @FocusState private var nameFocused: Bool
  @State private var hover: CGPoint?  // cursor over the preview — show the loupe

  let loupeSize: CGFloat = 380
  let loupeZoom: CGFloat = 2.5

  var body: some View {
    VStack(spacing: 16) {
      previewArea
      controls
    }
    .padding(.horizontal, 20)
    .padding(.top, 4)
    .padding(.bottom, 20)
    .background(backdrop)
    .preferredColorScheme(.dark)
  }

  // Blurred screenshot under the glass.
  var backdrop: some View {
    Color.black
      .overlay {
        if let image = model.preview {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .blur(radius: 70)
            .opacity(0.6)
        }
      }
      .clipped()
      .ignoresSafeArea()
  }

  var previewArea: some View {
    Group {
      if let image = model.preview {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
          .overlay {
            if model.loupeEnabled, let point = demoMode ? demoLoupePoint : hover { loupe(image, at: point) }
          }
          .onContinuousHover { phase in
            switch phase {
            case .active(let point): hover = point
            case .ended: hover = nil
            }
          }
          .onDrag {
            model.current.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
          }
          .help("Drag into a chat or another app")
      } else {
        Image(systemName: "film")
          .font(.system(size: 64))
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: model.previewSize.width, height: model.previewSize.height)
  }

  // SCREENSHOOTER_DEMO_LOUPE="0.6,0.4" — show the loupe at that point of the preview without a cursor.
  var demoLoupePoint: CGPoint? {
    guard let parts = launchEnvironment["SCREENSHOOTER_DEMO_LOUPE"]?.split(separator: ",").compactMap({ Double($0) }),
      parts.count == 2
    else { return nil }
    return CGPoint(x: model.previewSize.width * parts[0], y: model.previewSize.height * parts[1])
  }

  // A circle with the magnified area under the cursor.
  func loupe(_ image: NSImage, at point: CGPoint) -> some View {
    let size = model.previewSize
    return Image(nsImage: image)
      .resizable()
      .frame(width: size.width * loupeZoom, height: size.height * loupeZoom)
      .offset(x: loupeSize / 2 - point.x * loupeZoom, y: loupeSize / 2 - point.y * loupeZoom)
      .frame(width: loupeSize, height: loupeSize, alignment: .topLeading)
      .background(.black)
      .clipShape(Circle())
      .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
      .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
      .position(point)
      .allowsHitTesting(false)
  }

  var controls: some View {
    GlassEffectContainer(spacing: 12) {
      FlowLayout(spacing: 10) {
        if let category = model.opened {
          chip(id: "back", key: "esc", symbol: "chevron.left", action: model.back)
          chip(id: category.folder, key: "1", title: category.label) { model.pickSubfolder(nil) }
          ForEach(Array(model.subfolders.enumerated()), id: \.element) { index, name in
            chip(id: category.folder + "/" + name, key: index < 8 ? "\(index + 2)" : nil, title: name) {
              model.pickSubfolder(name)
            }
          }
          if model.naming {
            nameField
          } else {
            chip(id: "new", key: "N", title: "Folder", symbol: "plus", action: model.startNaming)
          }
        } else {
          ForEach(Array(categories.enumerated()), id: \.element) { index, category in
            chip(
              id: category.folder, key: "\(index + 1)", title: category.label,
              symbol: category.hasSubfolders ? "chevron.right" : nil
            ) { model.pick(category) }
          }
        }
        chip(
          id: "loupe", key: "RMB", symbol: model.loupeEnabled ? "plus.magnifyingglass" : "magnifyingglass",
          tint: model.loupeEnabled ? .blue : nil
        ) { model.loupeEnabled.toggle() }
          .help(model.loupeEnabled ? "Loupe on — right-click to turn off" : "Loupe off — right-click to turn on")
        chip(id: "delete", key: "⌫", symbol: "trash", tint: .red, action: model.deleteCurrent)
          .help("Move to Trash")
      }
    }
    .frame(width: model.previewSize.width)
  }

  func chip(
    id: String, key: String?, title: String? = nil, symbol: String? = nil, tint: Color? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let symbol, title == nil { Image(systemName: symbol) }
        if let key { KeyCap(key: key) }
        if let title { Text(title).font(.system(size: 15, weight: .medium)) }
        if let symbol, title != nil {
          Image(systemName: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.tint(tint?.opacity(0.35)).interactive(), in: .capsule)
    .glassEffectID(id, in: glass)
  }

  var nameField: some View {
    HStack(spacing: 8) {
      Image(systemName: "folder.badge.plus")
        .foregroundStyle(.secondary)
      TextField("New folder", text: $model.newName)
        .textFieldStyle(.plain)
        .frame(width: 180)
        .focused($nameFocused)
        .onSubmit(model.createFolder)
      KeyCap(key: "↩")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .glassEffect(.regular, in: .capsule)
    .glassEffectID("new", in: glass)
    .onAppear { DispatchQueue.main.async { nameFocused = true } }
  }
}
