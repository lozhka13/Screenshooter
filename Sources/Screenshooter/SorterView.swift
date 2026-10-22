// The window content: preview with loupe, secrets and marks, glass buttons.
import QuickLookThumbnailing
import ScreenshooterCore
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
  @FocusState private var textFocused: Bool
  @State private var hover: CGPoint?  // cursor over the preview — show the loupe
  @State private var drawing: Mark?  // the mark being dragged out
  @State private var markText = ""

  let loupeSize: CGFloat = 380
  let sidebarWidth = sidebarColumn
  let loupeZoom: CGFloat = 2.5

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      if model.showsSidebar && !model.allDone { sidebar }
      VStack(spacing: 16) {
        previewArea
        controls
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 4)
    .padding(.bottom, 20)
    .background(backdrop)
    .preferredColorScheme(.dark)
  }

  // Thumbnails of everything waiting, like the page sidebar in Preview; click or ← → to switch.
  var sidebar: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 12) {
          ForEach(Array(model.items.enumerated()), id: \.element) { index, url in
            QueueThumbnail(url: url, number: model.done + index + 1, selected: url == model.current)
              .id(url)
              .onTapGesture { model.select(url) }
              .help(url.lastPathComponent)
          }
        }
        .padding(10)
      }
      .onChange(of: model.current) { _, url in
        guard let url else { return }
        withAnimation { proxy.scrollTo(url, anchor: .center) }
      }
    }
    .frame(width: sidebarWidth, height: model.previewSize.height)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    ZStack {
      if model.allDone {
        allDoneView
      } else if let image = model.preview {
        if model.editing { editor(image) } else { picture(image) }
      } else {
        ProgressView().controlSize(.large)
      }
    }
    .frame(width: model.previewSize.width, height: model.previewSize.height)
    .overlay(alignment: .top) {
      if let toast = model.toast {
        Text(toast)
          .font(.system(size: 14, weight: .semibold))
          .padding(.horizontal, 16)
          .padding(.vertical, 9)
          .glassEffect(.regular, in: .capsule)
          .padding(.top, 14)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }

  var allDoneView: some View {
    VStack(spacing: 14) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 64))
        .foregroundStyle(.green)
      Text("All sorted")
        .font(.system(size: 26, weight: .semibold, design: .rounded))
      Text("⌘Z undoes the last one, Esc closes the window")
        .foregroundStyle(.secondary)
    }
  }

  func picture(_ image: NSImage) -> some View {
    Image(nsImage: image)
      .resizable()
      .scaledToFit()
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
      .overlay { secretBoxes }
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
  }

  // Red frames around passwords and tokens found in the text.
  var secretBoxes: some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(model.secrets.enumerated()), id: \.offset) { _, box in
        RoundedRectangle(cornerRadius: 4)
          .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
          .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
          .frame(width: box.width * model.previewSize.width + 8, height: box.height * model.previewSize.height + 6)
          .offset(x: box.minX * model.previewSize.width - 4, y: box.minY * model.previewSize.height - 3)
      }
    }
    .frame(width: model.previewSize.width, height: model.previewSize.height, alignment: .topLeading)
    .allowsHitTesting(false)
  }

  // Drag to draw the current tool; with the text tool, click to place text.
  func editor(_ image: NSImage) -> some View {
    let size = model.previewSize
    let normalized = { (p: CGPoint) in
      CGPoint(x: min(max(p.x / size.width, 0), 1), y: min(max(p.y / size.height, 0), 1))
    }
    return Image(nsImage: image)
      .resizable()
      .scaledToFit()
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay { MarksOverlay(marks: model.marks + (drawing.map { [$0] } ?? []), size: size, image: image) }
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(markColor).opacity(0.8), lineWidth: 2))
      .overlay(alignment: .topLeading) {
        if let point = model.textPoint {
          TextField("Text", text: $markText)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .bold))
            .clearable($markText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 220)
            .background(Color(markColor), in: RoundedRectangle(cornerRadius: 6))
            .focused($textFocused)
            .offset(x: point.x * size.width, y: point.y * size.height)
            .onAppear { DispatchQueue.main.async { textFocused = true } }
            .onSubmit {
              if !markText.isEmpty { model.marks.append(Mark(tool: .text, start: point, end: point, text: markText)) }
              markText = ""
              model.textPoint = nil
            }
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard model.tool != .text else { return }
            drawing = Mark(tool: model.tool, start: normalized(value.startLocation), end: normalized(value.location))
          }
          .onEnded { value in
            if model.tool == .text {
              markText = ""
              model.textPoint = normalized(value.location)
            } else if let mark = drawing, hypot(value.translation.width, value.translation.height) > 4 {
              model.marks.append(mark)
            }
            drawing = nil
          })
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
        if model.allDone {
          chip(id: "undo", key: "⌘Z", title: L("Undo"), symbol: "arrow.uturn.backward", action: model.undo)
          chip(id: "close", key: "esc", title: L("Close"), symbol: "xmark", action: model.finishBatch)
        } else if model.editing {
          editorButtons
        } else if let category = model.opened {
          subfolderButtons(category)
        } else {
          categoryButtons
        }
        if !model.allDone && !model.editing { toolButtons }
      }
    }
    .frame(width: model.previewSize.width)
  }

  @ViewBuilder var categoryButtons: some View {
    if let suggestion = model.suggestion {
      chip(id: "suggestion", key: "↩", title: suggestion.label, symbol: "sparkles", tint: .accentColor,
        action: model.acceptSuggestion)
        .help("Suggested from similar screenshots")
    }
    ForEach(Array(model.categories.enumerated()), id: \.element) { index, category in
      chip(
        id: category.folder, key: "\(index + 1)", title: category.label,
        symbol: category.hasSubfolders ? "chevron.right" : nil,
        tint: model.suggestion?.category == category ? .accentColor.opacity(0.5) : nil
      ) { model.pick(category) }
    }
  }

  @ViewBuilder func subfolderButtons(_ category: SortCategory) -> some View {
    chip(id: "back", key: "esc", symbol: "chevron.left", action: model.back)
    chip(id: category.folder, key: "1", title: category.label) { model.pickSubfolder(nil) }
    ForEach(Array(model.subfolders.enumerated()), id: \.element) { index, name in
      chip(
        id: category.folder + "/" + name, key: index < 8 ? "\(index + 2)" : nil, title: name,
        tint: model.suggestion?.category == category && model.suggestion?.subfolder == name ? .accentColor.opacity(0.5) : nil
      ) { model.pickSubfolder(name) }
    }
    if model.naming {
      nameField
    } else {
      chip(id: "new", key: "N", title: L("Folder"), symbol: "plus", action: model.startNaming)
    }
  }

  @ViewBuilder var editorButtons: some View {
    chip(id: "cancel", key: "esc", title: L("Cancel"), action: model.cancelEditing)
    ForEach(Tool.allCases, id: \.self) { tool in
      chip(id: "tool-\(tool.rawValue)", key: tool.key, symbol: tool.symbol, tint: model.tool == tool ? .accentColor : nil) {
        model.tool = tool
      }
    }
    chip(id: "save", key: "↩", title: L("Save"), symbol: "checkmark", tint: .green, action: model.saveEdits)
  }

  @ViewBuilder var toolButtons: some View {
    if !model.secrets.isEmpty {
      chip(id: "secrets", key: "R", title: "\(model.secrets.count)", symbol: "exclamationmark.shield", tint: .orange,
        action: model.redactSecrets)
        .help("Possible passwords or tokens — press R to blur them")
    }
    toolCluster
    if !model.history.isEmpty {
      chip(id: "undo", key: "⌘Z", symbol: "arrow.uturn.backward", action: model.undo)
        .help("Undo the last sort")
    }
    chip(id: "delete", key: "⌫", symbol: "trash", tint: .red, action: model.deleteCurrent)
      .help("Move to Trash")
  }

  // Everyday actions in one capsule: icon on top, key below.
  var toolCluster: some View {
    let video = model.current.map(isVideo) ?? false
    return HStack(spacing: 2) {
      if !video {
        tool("pencil.tip", "E", "Draw arrows, boxes, text or blur", action: model.startEditing)
      }
      tool("doc.on.doc", "C", "Copy to the clipboard", action: model.copyCurrent)
      tool("text.viewfinder", "T", "Copy the text", action: model.copyText)
      if video {
        tool("photo.stack", "G", "Make a GIF", action: model.makeGIF)
      } else {
        tool("pin", "P", "Pin on top of other windows", action: model.pinCurrent)
        tool("wand.and.stars", "B", "Style: background, rounded corners, shadow", action: model.beautifyCurrent)
      }
      tool(
        model.loupeEnabled ? "plus.magnifyingglass" : "magnifyingglass", "RMB",
        model.loupeEnabled ? "Loupe on — right-click to turn off" : "Loupe off — right-click to turn on",
        active: model.loupeEnabled
      ) { model.loupeEnabled.toggle() }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .glassEffect(.regular, in: .capsule)
    .glassEffectID("tools", in: glass)
  }

  func tool(_ symbol: String, _ key: String, _ help: String, active: Bool = false, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: symbol).font(.system(size: 15, weight: .medium))
        Text(key).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
      }
      .foregroundStyle(active ? Color.accentColor : .primary)
      .frame(width: 40, height: 38)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(L(help))
  }

  func chip(
    id: String, key: String?, title: String? = nil, symbol: String? = nil, tint: Color? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let symbol, title == nil { Image(systemName: symbol) }
        if let key { KeyCap(key: key) }
        if let title { Text(title).font(.system(size: 15, weight: .medium)).lineLimit(1) }
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
        .clearable($model.newName)
      KeyCap(key: "↩")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .glassEffect(.regular, in: .capsule)
    .glassEffectID("new", in: glass)
    .onAppear { DispatchQueue.main.async { nameFocused = true } }
  }
}

// Sidebar width; AppDelegate.fitPreview leaves room for it plus the gap.
let sidebarColumn: CGFloat = 132

struct QueueThumbnail: View {
  let url: URL
  let number: Int
  let selected: Bool
  @State private var image: NSImage?

  var body: some View {
    VStack(spacing: 5) {
      ZStack {
        if let image {
          Image(nsImage: image).resizable().scaledToFit()
        } else {
          RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)).frame(height: 66)
        }
        if isVideo(url) {
          Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.white).shadow(radius: 3)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(selected ? Color.accentColor : .white.opacity(0.12), lineWidth: selected ? 3 : 1)
          .padding(-3))
      Text("\(number)")
        .font(.system(size: 11, weight: selected ? .bold : .regular, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(selected ? .primary : .secondary)
    }
    .contentShape(Rectangle())
    .task(id: url) {
      let request = QLThumbnailGenerator.Request(
        fileAt: url, size: CGSize(width: 220, height: 160), scale: 2, representationTypes: .thumbnail)
      image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
  }
}
