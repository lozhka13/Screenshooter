import Foundation
import Testing

@testable import ScreenshooterCore

struct SuggesterTests {
  let categories = [
    SortCategory(label: "Work", folder: "Work", hasSubfolders: false),
    SortCategory(label: "Projects", folder: "Projects", hasSubfolders: true, keywords: ["orbit.coffee"]),
  ]

  func makeSuggester() -> Suggester {
    Suggester(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
  }

  @Test func sameHostSuggestsSameFolder() {
    let suggester = makeSuggester()
    let dashboard = ShotMetadata(appBundleID: "com.google.Chrome", url: "https://grafana.example.com/d/cpu")
    suggester.learn(dashboard, folder: "Work", file: "a.png")
    let next = ShotMetadata(appBundleID: "com.google.Chrome", url: "https://www.grafana.example.com/d/mem")
    #expect(suggester.suggest(next, categories: categories)?.category.folder == "Work")
  }

  @Test func browserAloneIsNotEnough() {
    let suggester = makeSuggester()
    suggester.learn(ShotMetadata(appBundleID: "com.google.Chrome", url: "https://a.com"), folder: "Work", file: "a.png")
    let other = ShotMetadata(appBundleID: "com.google.Chrome", url: "https://b.com")
    #expect(suggester.suggest(other, categories: categories) == nil)
  }

  @Test func sharedWordsSuggest() {
    let suggester = makeSuggester()
    let text = "billing renewSubscription payments invoice webhooks retries"
    suggester.learn(ShotMetadata(appBundleID: "com.microsoft.VSCode", text: text), folder: "Work", file: "a.png")
    let next = ShotMetadata(appBundleID: "com.microsoft.VSCode", text: text + " notifyOwner")
    #expect(suggester.suggest(next, categories: categories)?.category.folder == "Work")
  }

  @Test func fewCommonWordsDontSuggest() {
    let suggester = makeSuggester()
    suggester.learn(ShotMetadata(text: "settings overview dashboard revenue churn customers"), folder: "Work", file: "a.png")
    let other = ShotMetadata(text: "settings overview coffee beans roast subscription farms")
    #expect(suggester.suggest(other, categories: categories) == nil)
  }

  @Test func categoryKeywords() {
    let landing = ShotMetadata(url: "https://orbit.coffee/beans")
    #expect(makeSuggester().suggest(landing, categories: categories)?.category.folder == "Projects")
  }

  @Test func forgetUndoesLearning() {
    let suggester = makeSuggester()
    let shot = ShotMetadata(url: "https://grafana.example.com")
    suggester.learn(shot, folder: "Work", file: "Work/a.png")
    suggester.forget(file: "Work/a.png")
    #expect(suggester.suggest(shot, categories: categories) == nil)
  }

  @Test func keywordsAreFrequentLongWords() {
    #expect(Suggester.keywords(in: "the coffee COFFEE beans roast a an") == ["coffee", "beans", "roast"])
  }
}
