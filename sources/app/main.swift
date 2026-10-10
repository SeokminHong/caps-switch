import AppKit
import CapsSwitchCore
import Foundation

if CommandLine.arguments.contains("--version") {
  guard
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  else {
    fputs("앱 번들의 버전을 확인할 수 없습니다. 빌드한 앱에서 실행해 주세요.\n", stderr)
    exit(1)
  }
  print("caps-switch \(version)")
} else if CommandLine.arguments.contains("--check-guide") {
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
