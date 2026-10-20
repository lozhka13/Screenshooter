// Одно окно для разбора скриншотов и записей экрана из ~/Screenshots/Inbox.
// Предпросмотр, прогресс m / n, стеклянные кнопки (Liquid Glass, macOS 26):
//   1/2/3 — категория; в категории с подпапками 1 — в корень, 2…9 — подпапка,
//   N — новая папка, Esc — назад; Delete — в Корзину.
// Подпапки берутся с диска: ~/Screenshots/<категория>/<подпапка>.
// После переноса файл сжимается в фоне (~/bin/screenshot-compress.sh).
// Сборка и установка: ./install.sh
// Запускается launchd (com.screenshooter.sorter) при изменении Inbox.
import AVFoundation
import Cocoa
import SwiftUI

struct Category: Hashable {
  let label: String
  let folder: String
  let hasSubfolders: Bool
}

// Новая категория — новая строка; шорткат = порядковый номер.
let categories = [
  Category(label: "Wingform", folder: "Wingform", hasSubfolders: false),
  Category(label: "Вёрстка", folder: "Verstka", hasSubfolders: true),
  Category(label: "Личное", folder: "Личное", hasSubfolders: true),
]

let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots")
let inbox = base.appendingPathComponent("Inbox")
let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
let videoExtensions: Set<String> = ["mov", "mp4"]

// MARK: - Model

@MainActor
final class SorterModel: ObservableObject {
  @Published var current: URL?
  @Published var preview: NSImage?
  @Published var queue: [URL] = []
  @Published var done = 0
  @Published var opened: Category?  // категория, в которой выбираем подпапку
  @Published var subfolders: [String] = []
  @Published var naming = false
  @Published var newName = ""
  @Published var previewSize = CGSize(width: 1200, height: 750)  // окно подстраивается под него
  @Published var loupeEnabled = !UserDefaults.standard.bool(forKey: "loupeOff") {  // правая кнопка мыши
    didSet { UserDefaults.standard.set(!loupeEnabled, forKey: "loupeOff") }
  }

  var lastSizes: [URL: Int] = [:]  // файл попадает в очередь, когда размер перестал меняться
  var onShow: () -> Void = {}
  var onHide: () -> Void = {}
  var onTitle: (String) -> Void = { _ in }
  var onCount: (Int) -> Void = { _ in }
  var onLayout: () -> Void = {}
  var onToggleLarge: () -> Void = {}
  var hiddenByUser = false  // свернули в трей — новые снимки окно не открывают
  let compressor: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  var progress: String { "\(done + 1) / \(done + 1 + queue.count)" }

  // Прогресс и имя файла — в заголовке окна.
  func updateTitle() {
    onTitle(current.map { "\(progress)  ·  \($0.lastPathComponent)" } ?? "Скриншоты")
    onCount((current == nil ? 0 : 1) + queue.count)
  }

  func candidates() -> [URL] {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: inbox, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
    let all = imageExtensions.union(videoExtensions)
    return urls
      .filter { all.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }

  func scan() {
    if let url = current, !FileManager.default.fileExists(atPath: url.path) {
      current = nil  // файл убрали из Inbox вручную
    }
    let files = candidates()
    if files.isEmpty && current == nil && compressor.operationCount == 0 {
      NSApp.terminate(nil)
      return
    }
    lastSizes = lastSizes.filter { files.contains($0.key) }  // забываем исчезнувшие файлы
    for url in files where url != current && !queue.contains(url) {
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
      if lastSizes[url] == size {
        queue.append(url)
      } else {
        lastSizes[url] = size
      }
    }
    if current == nil { showNext() }
    updateTitle()
  }

  func showNext() {
    queue.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
    opened = nil
    naming = false
    guard !queue.isEmpty else {
      current = nil
      preview = nil
      done = 0
      onHide()
      return
    }
    let url = queue.removeFirst()
    current = url
    updateTitle()
    guard videoExtensions.contains(url.pathExtension.lowercased()) else {
      preview = NSImage(contentsOf: url)
      onLayout()
      onShow()
      return
    }
    // Кадр из видео достаём асинхронно, чтобы окно не подвисало.
    preview = nil
    onShow()
    Task {
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
      generator.appliesPreferredTrackTransform = true
      guard let (frame, _) = try? await generator.image(at: .zero), current == url else { return }
      preview = NSImage(cgImage: frame, size: .zero)
      onLayout()
    }
  }

  func folderURL(_ category: Category) -> URL {
    base.appendingPathComponent(category.folder)
  }

  func listSubfolders(_ category: Category) -> [String] {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: folderURL(category), includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])) ?? []
    return urls
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .map(\.lastPathComponent)
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  // MARK: Actions

  func pick(_ category: Category) {
    guard current != nil else { return }
    guard category.hasSubfolders else {
      move(to: folderURL(category))
      return
    }
    subfolders = listSubfolders(category)
    withAnimation(.bouncy) { opened = category }
  }

  func pickSubfolder(_ name: String?) {
    guard let category = opened else { return }
    let folder = folderURL(category)
    move(to: name.map { folder.appendingPathComponent($0) } ?? folder)
  }

  func back() {
    withAnimation(.bouncy) {
      if naming {
        naming = false
      } else {
        opened = nil
      }
    }
  }

  func startNaming() {
    guard opened != nil else { return }
    newName = ""
    withAnimation(.bouncy) { naming = true }
  }

  func createFolder() {
    let name = newName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/", with: "-")
    guard let category = opened, !name.isEmpty, !name.hasPrefix(".") else {
      NSSound.beep()
      return
    }
    try? FileManager.default.createDirectory(
      at: folderURL(category).appendingPathComponent(name), withIntermediateDirectories: true)
    pickSubfolder(name)
  }

  func move(to folder: URL) {
    guard let url = current else { return }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var destination = folder.appendingPathComponent(url.lastPathComponent)
    var copy = 2
    while FileManager.default.fileExists(atPath: destination.path) {
      let name = "\(url.deletingPathExtension().lastPathComponent) \(copy).\(url.pathExtension)"
      destination = folder.appendingPathComponent(name)
      copy += 1
    }
    do {
      try FileManager.default.moveItem(at: url, to: destination)
    } catch {
      NSSound.beep()
      return
    }
    compress(destination)
    finishCurrent()
  }

  func deleteCurrent() {
    guard let url = current else { return }
    do {
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    } catch {
      NSSound.beep()
      return
    }
    finishCurrent()
  }

  func finishCurrent() {
    guard let url = current else { return }
    lastSizes[url] = nil
    current = nil
    done += 1
    showNext()
  }

  // Сжатие в фоне, по одному файлу и с низким приоритетом.
  func compress(_ url: URL) {
    compressor.addOperation {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
      process.arguments = ["-n", "15", NSHomeDirectory() + "/bin/screenshot-compress.sh", url.path]
      try? process.run()
      process.waitUntilExit()
    }
  }

  // Возвращает true, если клавиша обработана.
  func handleKey(_ event: NSEvent) -> Bool {
    guard current != nil else { return false }
    if naming {
      if event.keyCode == 53 {
        back()
        return true
      }
      return false  // остальное — в поле ввода
    }
    // Автоповтор зажатой клавиши разобрал бы несколько файлов подряд.
    if event.isARepeat { return true }
    switch event.keyCode {
    case 51, 117:  // Delete, Fn+Delete
      deleteCurrent()
      return true
    case 53:  // Esc
      guard opened != nil else { return false }
      back()
      return true
    case 45:  // N (в любой раскладке)
      guard opened != nil else { return false }
      startNaming()
      return true
    case 3:  // F — на всю ширину экрана и обратно
      onToggleLarge()
      return true
    default:
      break
    }
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
      let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) })
    else { return false }
    if opened != nil {
      // 1 — сама категория, 2…9 — подпапки.
      if digit == 1 {
        pickSubfolder(nil)
        return true
      }
      if digit >= 2 && digit - 2 < subfolders.count {
        pickSubfolder(subfolders[digit - 2])
        return true
      }
    } else if (1...categories.count).contains(digit) {
      pick(categories[digit - 1])
      return true
    }
    return false
  }
}

// MARK: - Views

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

// Кнопки переносятся на новую строку, строки по центру.
struct FlowLayout: Layout {
  var spacing: CGFloat = 10

  struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  // Размеры кнопок меряем один раз на изменение содержимого.
  func makeCache(subviews: Subviews) -> [CGSize] {
    subviews.map { $0.sizeThatFits(.unspecified) }
  }

  func updateCache(_ cache: inout [CGSize], subviews: Subviews) {
    cache = makeCache(subviews: subviews)
  }

  func rows(_ maxWidth: CGFloat, _ sizes: [CGSize]) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for (index, size) in sizes.enumerated() {
      let width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      if width > maxWidth && !row.indices.isEmpty {
        rows.append(row)
        row = Row(indices: [index], width: size.width, height: size.height)
      } else {
        row.indices.append(index)
        row.width = width
        row.height = max(row.height, size.height)
      }
    }
    if !row.indices.isEmpty { rows.append(row) }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
    let rows = rows(proposal.width ?? .infinity, cache)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
    var y = bounds.minY
    for row in rows(bounds.width, cache) {
      var x = bounds.minX + (bounds.width - row.width) / 2
      for index in row.indices {
        let size = cache[index]
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }
}

struct SorterView: View {
  @ObservedObject var model: SorterModel
  @Namespace private var glass
  @FocusState private var nameFocused: Bool
  @State private var hover: CGPoint?  // курсор над предпросмотром — показываем лупу

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

  // Размытый скриншот под стеклом.
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
            if model.loupeEnabled, let point = hover { loupe(image, at: point) }
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
          .help("Перетащите в чат или другое приложение")
      } else {
        Image(systemName: "film")
          .font(.system(size: 64))
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: model.previewSize.width, height: model.previewSize.height)
  }

  // Круг с увеличенным участком картинки под курсором.
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
            chip(id: "new", key: "N", title: "Папка", symbol: "plus", action: model.startNaming)
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
          id: "loupe", key: "ПКМ", symbol: model.loupeEnabled ? "plus.magnifyingglass" : "magnifyingglass",
          tint: model.loupeEnabled ? .blue : nil
        ) { model.loupeEnabled.toggle() }
          .help(model.loupeEnabled ? "Лупа включена — правая кнопка мыши выключает" : "Лупа выключена — правая кнопка мыши включает")
        chip(id: "delete", key: "⌫", symbol: "trash", tint: .red, action: model.deleteCurrent)
          .help("В Корзину")
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
      TextField("Новая папка", text: $model.newName)
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

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var window: NSWindow!
  var statusItem: NSStatusItem!
  var scanTimer: Timer?
  let model = MainActor.assumeIsolated { SorterModel() }
  var large = UserDefaults.standard.bool(forKey: "large") {
    didSet { UserDefaults.standard.set(large, forKey: "large") }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.title = "Скриншоты"
    window.level = .floating
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.delegate = self
    // Не попадает в скриншоты и записи экрана (SORTER_VISIBLE=1 — для отладки).
    window.sharingType = ProcessInfo.processInfo.environment["SORTER_VISIBLE"] == nil ? .none : .readOnly

    let hosting = NSHostingView(rootView: SorterView(model: model))
    hosting.sizingOptions = [.minSize, .maxSize]  // окно = размер предпросмотра + кнопки
    window.contentView = hosting
    window.collectionBehavior = [.fullScreenNone]

    // Жёлтая — в трей, зелёная — на всю ширину экрана.
    window.standardWindowButton(.miniaturizeButton)?.target = self
    window.standardWindowButton(.miniaturizeButton)?.action = #selector(hideToTray)
    window.standardWindowButton(.zoomButton)?.target = self
    window.standardWindowButton(.zoomButton)?.action = #selector(toggleLarge)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Скриншоты")
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

    MainActor.assumeIsolated {
      model.onLayout = { [weak self] in self?.fitPreview() }
      model.onToggleLarge = { [weak self] in self?.toggleLarge() }
      model.onCount = { [weak self] count in
        self?.statusItem.button?.title = count > 0 ? " \(count)" : ""
      }
      model.onShow = { [weak self] in
        guard let self, let window = self.window, !window.isVisible,
          !MainActor.assumeIsolated({ self.model.hiddenByUser })
        else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { window.center() }  // после того как окно приняло новый размер
      }
      model.onHide = { [weak self] in self?.window.orderOut(nil) }
      model.onTitle = { [weak self] title in self?.window.title = title }
      model.scan()
    }

    // Клавиши — только когда окно на экране и в фокусе, иначе разберём файл вслепую.
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.window, self.window.isVisible else { return event }
      return MainActor.assumeIsolated { self.model.handleKey(event) } ? nil : event
    }
    // Правая кнопка мыши в окне включает и выключает лупу.
    NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
      guard let self, event.window === self.window else { return event }
      MainActor.assumeIsolated { self.model.loupeEnabled.toggle() }
      return nil
    }
    scanTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let model = self?.model else { return }
      MainActor.assumeIsolated { model.scan() }
    }
  }

  // Окно меняет размер под каждую картинку — не даём ему уйти за край экрана.
  func windowDidResize(_ notification: Notification) {
    guard let visible = window.screen?.visibleFrame else { return }
    var origin = window.frame.origin
    origin.x = min(max(origin.x, visible.minX), visible.maxX - window.frame.width)
    origin.y = min(max(origin.y, visible.minY), visible.maxY - window.frame.height)
    if origin != window.frame.origin { window.setFrameOrigin(origin) }
  }

  // Предпросмотр по пропорциям картинки: до 1300 pt в ширину, не больше экрана.
  @MainActor func fitPreview() {
    guard let image = model.preview else { return }
    let rep = image.representations.first
    let aspect =
      (rep?.pixelsWide ?? 0) > 0
      ? CGFloat(rep!.pixelsWide) / CGFloat(max(rep!.pixelsHigh, 1))
      : image.size.width / max(image.size.height, 1)
    let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let maxWidth = large ? visible.width - 40 : min(1300, visible.width * 0.9 - 40)
    let maxHeight = (large ? visible.height : visible.height * 0.92) - 140  // заголовок, кнопки, отступы
    var size = CGSize(width: maxWidth, height: maxWidth / aspect)
    if size.height > maxHeight {
      size = CGSize(width: maxHeight * aspect, height: maxHeight)
    }
    model.previewSize = CGSize(width: size.width.rounded(), height: size.height.rounded())
  }

  @objc func toggleLarge() {
    large.toggle()
    MainActor.assumeIsolated { fitPreview() }
    DispatchQueue.main.async { [weak self] in self?.window.center() }
  }

  // Красная и жёлтая кнопки прячут окно в трей; остаток ждёт в Inbox.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideToTray()
    return false
  }

  @objc func hideToTray() {
    MainActor.assumeIsolated { model.hiddenByUser = true }
    window.orderOut(nil)
  }

  @objc func showFromTray() {
    let hasFile = MainActor.assumeIsolated {
      model.hiddenByUser = false
      return model.current != nil
    }
    guard hasFile else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc func statusClicked() {
    guard NSApp.currentEvent?.type == .rightMouseUp else {
      window.isVisible ? hideToTray() : showFromTray()
      return
    }
    let menu = NSMenu()
    menu.addItem(withTitle: "Показать", action: #selector(showFromTray), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Выйти", action: #selector(quit), keyEquivalent: "q").target = self
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  // Выход: остаток ждёт в Inbox до следующего снимка; начатое сжатие доделываем.
  @objc func quit() {
    scanTimer?.invalidate()  // новые снимки больше не открывают окно
    window.orderOut(nil)
    NSStatusBar.system.removeStatusItem(statusItem)
    let compressor = MainActor.assumeIsolated { model.compressor }
    DispatchQueue.global().async {
      compressor.waitUntilAllOperationsAreFinished()
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
