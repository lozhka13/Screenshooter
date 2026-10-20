import Foundation

// UI strings; English is the key, translations live in Resources/<language>.lproj/Localizable.strings.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
