import CapsSwitchCore
import Foundation

enum AppSettings {
  private static let targetKeyPreference = "targetFunctionKey"
  private static let mappingPreference = "mappingEnabled"

  static var targetKey: FunctionKey {
    get {
      FunctionKey(rawValue: UserDefaults.standard.integer(forKey: targetKeyPreference)) ?? .f18
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: targetKeyPreference) }
  }

  static var mappingEnabled: Bool {
    get { UserDefaults.standard.object(forKey: mappingPreference) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: mappingPreference) }
  }
}
