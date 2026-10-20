import Testing

@testable import ScreenshooterCore

struct SecretDetectorTests {
  func found(_ text: String) -> [String] {
    SecretDetector.secrets(in: text).map { String(text[$0]) }
  }

  @Test func labelledPasswords() {
    #expect(found("password: hunter2!") == ["hunter2!"])
    #expect(found("Пароль Qwerty123") == ["Qwerty123"])
    #expect(found("api_key=abcd1234efgh") == ["abcd1234efgh"])
  }

  @Test func labelsAloneAreNotSecrets() {
    #expect(found("Password").isEmpty)
    #expect(found("Password Rotated every 30 days").isEmpty)
    #expect(found("Forgot your password?").isEmpty)
  }

  @Test func randomLookingTokens() {
    #expect(found("admin Gjqa3PFC3DqMYc3u3TXCS7ftRkgAaAN1") == ["Gjqa3PFC3DqMYc3u3TXCS7ftRkgAaAN1"])
  }

  @Test func tokensReadWithCyrillicTwins() {
    #expect(found("admin Gjqa3PFC3DqMYсЗи3TХCS7ft") == ["Gjqa3PFC3DqMYсЗи3TХCS7ft"])
    #expect(found("Конфиденциальностьиспользования данных").isEmpty)
  }

  @Test func knownTokenFormats() {
    #expect(found("token ghp_abcdefghijklmnopqrstuvwxyz0123456789").count == 1)
    #expect(found("AKIAIOSFODNN7EXAMPLE") == ["AKIAIOSFODNN7EXAMPLE"])
    #expect(found("Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abcdefghijk").count == 1)
  }

  @Test func urlCredentials() {
    #expect(found("postgres://app:s3cretPass@db.internal:5432/app") == ["s3cretPass"])
  }

  @Test func cardNumbersPassLuhn() {
    #expect(found("Card 4242 4242 4242 4242") == ["4242 4242 4242 4242"])
    #expect(found("Order 1234 5678 9012 3456").isEmpty)
  }

  @Test func ordinaryTextIsNotSecret() {
    #expect(found("Revenue by week grew 12.4% in Q3").isEmpty)
    #expect(found("https://github.com/lozhka13/Screenshooter/releases").isEmpty)
    #expect(found("Single-origin coffee from small farms").isEmpty)
  }
}
