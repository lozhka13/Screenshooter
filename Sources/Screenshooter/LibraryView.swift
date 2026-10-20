// Library window: every screenshot and recording, searchable by its text, title, app and transcript.
import QuickLookThumbnailing
import ScreenshooterCore
import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
  @Published var query = ""
  @Published var scope = ""  // "" — everything, otherwise a folder inside ~/Screenshots
  @Published var results: [URL] = []
  @Published var unindexed = 0  // images whose text hasn't been recognized yet
  @Published var indexing = false
  private var searchTask: Task<Void, Never>?

  func search() {
    searchTask?.cancel()
    let query = query
    let scope = scope
    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(200))  // wait for typing to pause
      guard !Task.isCancelled else { return }
      let found = await Task.detached { Self.find(query, in: scope) }.value
      guard !Task.isCancelled else { return }
      results = found.files
      unindexed = found.unindexed
    }
  }

  nonisolated static func find(_ query: String, in scope: String) -> (files: [URL], unindexed: Int) {
    let folder = scope.isEmpty ? base : base.appendingPathComponent(scope)
    let words = query.lowercased().split(separator: " ").map(String.init)
    var files: [URL] = []
    var unindexed = 0
    for url in Library.mediaFiles(in: folder) {
      let metadata = ShotMetadata.read(url)
      if metadata?.text == nil && !isVideo(url) { unindexed += 1 }
      if !words.isEmpty {
        var haystack = url.lastPathComponent.lowercased() + "\n" + (metadata?.searchableText ?? "")
        if isVideo(url), let transcript = try? String(contentsOf: transcriptURL(for: url), encoding: .utf8) {
          haystack += "\n" + transcript.lowercased()
        }
        guard words.allSatisfy(haystack.contains) else { continue }
      }
      files.append(url)
      if files.count >= 400 { break }
    }
    return (files, unindexed)
  }

  // Recognizes text on screenshots sorted before text search existed.
  func indexAll() {
    indexing = true
    Task {
      for url in Library.mediaFiles(in: base) where !isVideo(url) && ShotMetadata.read(url)?.text == nil {
        _ = await TextRecognizer.text(of: url)
        unindexed = max(0, unindexed - 1)
      }
      indexing = false
      search()
    }
  }
}

struct LibraryView: View {
  @StateObject private var model = LibraryModel()
  var initialQuery = ""
  @FocusState private var searchFocused: Bool
  private let categories = CategoryStore.load()

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search text, titles, apps and transcripts", text: $model.query)
          .textFieldStyle(.plain)
          .font(.title3)
          .focused($searchFocused)
        Picker("", selection: $model.scope) {
          Text("Everything").tag("")
          Text("Inbox").tag("Inbox")
          ForEach(categories) { Text($0.label).tag($0.folder) }
        }
        .labelsHidden()
        .frame(width: 170)
      }
      .padding(14)
      if model.unindexed > 0 {
        HStack {
          Text(String(format: L("%d screenshots aren't searchable by text yet"), model.unindexed))
          Spacer()
          Button(model.indexing ? L("Indexing…") : L("Index Now"), action: model.indexAll).disabled(model.indexing)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
      }
      Divider()
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
          ForEach(model.results, id: \.self) { ThumbnailCell(url: $0) }
        }
        .padding(16)
      }
      .overlay {
        if model.results.isEmpty {
          Text(model.query.isEmpty ? "No screenshots yet" : "Nothing found").foregroundStyle(.secondary)
        }
      }
    }
    .frame(minWidth: 760, minHeight: 500)
    .onChange(of: model.query) { model.search() }
    .onChange(of: model.scope) { model.search() }
    .onAppear {
      if model.query.isEmpty { model.query = initialQuery }
      model.search()
      searchFocused = true
    }
  }
}

struct ThumbnailCell: View {
  let url: URL
  @State private var image: NSImage?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: 10).fill(.quaternary)
        if let image {
          Image(nsImage: image).resizable().scaledToFit()
        } else {
          ProgressView().controlSize(.small)
        }
        if isVideo(url) {
          Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white).shadow(radius: 4)
        }
      }
      .frame(height: 130)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      Text(url.deletingPathExtension().lastPathComponent).font(.caption).lineLimit(2)
      Text(Library.relativePath(url.deletingLastPathComponent())).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    .contextMenu {
      Button("Open") { NSWorkspace.shared.open(url) }
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
      Button("Copy") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
      }
      Button("Copy Text") {
        Task {
          let text = await TextRecognizer.text(of: url)
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
      }
      if !isVideo(url) { Button("Pin") { Pins.pin(url) } }
    }
    .task(id: url) {
      let request = QLThumbnailGenerator.Request(
        fileAt: url, size: CGSize(width: 400, height: 260), scale: 2, representationTypes: .thumbnail)
      image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
  }
}
