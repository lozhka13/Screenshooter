// Settings window: general options, categories, recording, Claude, about.
import ScreenshooterCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
      CategoriesSettings().tabItem { Label("Categories", systemImage: "folder") }
      RecordingSettings().tabItem { Label("Recording", systemImage: "record.circle") }
      ClaudeSettings().tabItem { Label("Claude", systemImage: "sparkles") }
      AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
    }
    .padding(20)
    .frame(width: 640, height: 480)
  }
}

struct GeneralSettings: View {
  @AppStorage("renameFiles") var renameFiles = true
  @AppStorage("suggestFolders") var suggestFolders = true
  @AppStorage("detectSecrets") var detectSecrets = true
  @AppStorage("compress") var compress = true
  @AppStorage("smartNames") var smartNames = true
  @State var openAtLogin = SMAppService.mainApp.status == .enabled

  var compressionTools: Bool {
    ["ffmpeg", "oxipng"].allSatisfy { FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/\($0)") }
  }

  var body: some View {
    Form {
      Section {
        Toggle("Open at login", isOn: $openAtLogin)
          .onChange(of: openAtLogin) { _, enabled in
            try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            openAtLogin = SMAppService.mainApp.status == .enabled
          }
        if SMAppService.mainApp.status == .requiresApproval {
          Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
        }
      }
      Section("Sorting") {
        Toggle("Suggest a folder from similar screenshots", isOn: $suggestFolders)
        Toggle("Name files after the page or heading", isOn: $renameFiles)
        Toggle("Highlight passwords and tokens", isOn: $detectSecrets)
        Toggle("Smart names with Apple Intelligence", isOn: $smartNames)
        if !Summarizer.isAvailable {
          Text("Turn on Apple Intelligence in System Settings to name files from what the screen shows.")
            .foregroundStyle(.secondary)
        }
      }
      Section("Compression") {
        Toggle("Compress after sorting (PNG lossless, video H.265)", isOn: $compress)
        if !compressionTools {
          Text("Needs Homebrew tools: brew install ffmpeg oxipng").foregroundStyle(.orange)
        }
      }
      Section("Folders") {
        LabeledContent("Screenshots", value: inbox.path)
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([inbox]) }
      }
    }
    .formStyle(.grouped)
  }
}

struct CategoriesSettings: View {
  @State var items = CategoryStore.load()
  @State var status = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Up to 9 categories; the key is the position in the list. Keywords in a page address, title or text suggest the category.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      List {
        ForEach(items.indices, id: \.self) { index in
          HStack(spacing: 8) {
            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 14)
            TextField("Label", text: $items[index].label).frame(width: 110)
            TextField("Folder", text: $items[index].folder).frame(width: 110)
            Toggle("Subfolders", isOn: $items[index].hasSubfolders)
            TextField("Keywords", text: keywords(index))
            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
              .disabled(index == 0)
            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
              .disabled(index == items.count - 1)
            Button { items.remove(at: index) } label: { Image(systemName: "minus.circle") }
              .disabled(items.count == 1)
          }
          .buttonStyle(.borderless)
        }
      }
      HStack {
        Button("Add Category") {
          items.append(SortCategory(label: L("New"), folder: L("New"), hasSubfolders: false))
        }
        .disabled(items.count >= CategoryStore.maxCount)
        Button("Open categories.json") { NSWorkspace.shared.open(CategoryStore.fileURL) }
        Spacer()
        Text(status).foregroundStyle(.secondary)
        Button("Save") { save() }.keyboardShortcut(.defaultAction)
      }
    }
  }

  func keywords(_ index: Int) -> Binding<String> {
    Binding(
      get: { items[index].keywords.joined(separator: ", ") },
      set: { items[index].keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
  }

  func move(_ index: Int, by offset: Int) {
    items.swapAt(index, index + offset)
  }

  func save() {
    let cleaned = items.compactMap { item -> SortCategory? in
      guard let folder = Library.cleanFolderName(item.folder) else { return nil }
      let label = item.label.trimmingCharacters(in: .whitespaces)
      return SortCategory(label: label.isEmpty ? folder : label, folder: folder, hasSubfolders: item.hasSubfolders, keywords: item.keywords)
    }
    do {
      try CategoryStore.save(cleaned)
      items = cleaned
      status = L("Saved")
    } catch {
      status = error.localizedDescription
    }
  }
}

struct RecordingSettings: View {
  @AppStorage("recordSystemAudio") var systemAudio = true
  @AppStorage("recordMicrophone") var microphone = true
  @AppStorage("transcribe") var transcribe = true
  @AppStorage("transcriptionLocale") var locale = ""
  @State var locales: [Locale] = []

  var body: some View {
    Form {
      Section {
        LabeledContent("Start or stop recording", value: "⌃⌥⌘R")
        Toggle("Record system audio (calls, videos)", isOn: $systemAudio)
        Toggle("Record the microphone", isOn: $microphone)
      } footer: {
        Text("Recordings of the screen under the pointer go to Inbox and are sorted like screenshots.")
      }
      Section("Transcription") {
        Toggle("Transcribe recordings on this Mac", isOn: $transcribe)
        Picker("Language", selection: $locale) {
          Text("Automatic").tag("")
          ForEach(locales, id: \.self) { item in
            Text(Locale.current.localizedString(forIdentifier: item.identifier) ?? item.identifier)
              .tag(item.identifier(.bcp47))
          }
        }
        .disabled(!transcribe)
        Text("The transcript is saved next to the recording as a .txt file. Nothing leaves your Mac.")
          .foregroundStyle(.secondary)
      }
      Section("Permissions") {
        Button("Screen & System Audio Recording…") { openPrivacy("Privacy_ScreenCapture") }
        Button("Microphone…") { openPrivacy("Privacy_Microphone") }
        Button("Speech Recognition…") {
          Task { if !(await Transcriber.requestPermission()) { openPrivacy("Privacy_SpeechRecognition") } }
        }
      }
    }
    .formStyle(.grouped)
    .task { locales = await Transcriber.supportedLocales() }
  }

  func openPrivacy(_ pane: String) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
  }
}

struct ClaudeSettings: View {
  var mcpPath: String { Setup.mcpPath ?? "/Applications/Screenshooter.app/Contents/MacOS/screenshooter-mcp" }
  var command: String { "claude mcp add --scope user screenshooter \"\(mcpPath)\"" }
  var desktopConfig: String {
    """
    {
      "mcpServers": {
        "screenshooter": { "command": "\(mcpPath)" }
      }
    }
    """
  }

  var body: some View {
    Form {
      Section {
        Text("Claude can list, search, view and file your screenshots and read transcripts of recordings. It only sees ~/Screenshots.")
          .fixedSize(horizontal: false, vertical: true)
      }
      Section("Claude Code") {
        Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        Button("Copy Command") { copy(command) }
      }
      Section("Claude Desktop — claude_desktop_config.json") {
        Text(desktopConfig).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        Button("Copy Configuration") { copy(desktopConfig) }
      }
    }
    .formStyle(.grouped)
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}

struct AboutSettings: View {
  @AppStorage("checkForUpdates") var checkForUpdates = true

  var body: some View {
    VStack(spacing: 14) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
      Text("Screenshooter").font(.title.weight(.semibold))
      Text(String(format: L("Version %@"), Updater.currentVersion)).foregroundStyle(.secondary)
      Button("Check for Updates") { Task { await Updater.check(userInitiated: true) } }
      Toggle("Check for updates automatically", isOn: $checkForUpdates)
      HStack(spacing: 16) {
        Link("GitHub", destination: URL(string: "https://github.com/lozhka13/Screenshooter")!)
        Link("Security report", destination: URL(string: "https://github.com/lozhka13/Screenshooter/blob/main/docs/security-report.md")!)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
