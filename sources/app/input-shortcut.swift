import CapsSwitchCore
import Carbon
import Foundation

enum InputShortcut {
  private static let preferencesDomain = "com.apple.symbolichotkeys"
  private static let preferencesKey = "AppleSymbolicHotKeys"
  private static let previousInputSourceId = "60"
  private static let keyCodeParameter = 1
  private static let modifiersParameter = 2
  private static let parameterCount = 3

  static func isConfigured(for key: FunctionKey) -> Bool {
    CFPreferencesAppSynchronize(preferencesDomain as CFString)
    guard
      let shortcuts = CFPreferencesCopyAppValue(
        preferencesKey as CFString, preferencesDomain as CFString
      ) as? [String: Any],
      let previous = shortcuts[previousInputSourceId] as? [String: Any],
      previous["enabled"] as? Bool == true,
      let value = previous["value"] as? [String: Any],
      let parameters = value["parameters"] as? [NSNumber],
      parameters.count == parameterCount
    else { return false }
    return parameters[keyCodeParameter].uint32Value == key.keyCode
      && parameters[modifiersParameter].intValue == 0
  }
}
