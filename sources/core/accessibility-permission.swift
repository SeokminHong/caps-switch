import ApplicationServices

final class AccessibilityPermission {
  private let checkTrust: () -> Bool
  private let request: () -> Void
  private var hasRequested = false

  init(
    checkTrust: @escaping () -> Bool = { AXIsProcessTrusted() },
    request: @escaping () -> Void = {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
  ) {
    self.checkTrust = checkTrust
    self.request = request
  }

  var isTrusted: Bool { checkTrust() }

  func requestIfNeeded() {
    guard !isTrusted, !hasRequested else { return }
    hasRequested = true
    request()
  }
}
