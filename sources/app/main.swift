import AppKit
import CapsSwitchCore
import Foundation

if CommandLine.arguments.contains("--check-guide") {
  _ = NSApplication.shared
  do { try AppDelegate().checkGuideLayout() } catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
  }
} else if CommandLine.arguments.contains("--verify") {
  do { try runVerification() } catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
  }
} else {
  let application = NSApplication.shared
  let delegate = AppDelegate()
  application.delegate = delegate
  application.setActivationPolicy(.accessory)
  application.run()
}
