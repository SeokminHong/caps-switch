import AppKit
import CapsSwitchCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var session = MappingSession(targetKey: AppSettings.targetKey)
  private lazy var hotkey = CapsHotkey { [weak self] in
    do { try CapsLock.toggle() } catch { self?.showError(error) }
  }
  private var statusItem: NSStatusItem!
  private var window: NSWindow!
  private let statusLabel = NSTextField(wrappingLabelWithString: "사용 중지")
  private let shortcutLabel = NSTextField(wrappingLabelWithString: "")
  private let toggleButton = NSButton(title: "Caps Lock 전환 사용 시작", target: nil, action: nil)
  private var toggleMenuItem: NSMenuItem!
  private let keySelector = NSPopUpButton(frame: .zero, pullsDown: false)
  private let loginButton = NSButton(checkboxWithTitle: "로그인 시 자동 실행", target: nil, action: nil)
  private let guide = NSTextField(wrappingLabelWithString: "")

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureMenu()
    configureWindow()
    if AppSettings.mappingEnabled {
      do { try enableMapping() } catch { showError(error) }
    }
    refreshStatus()
    if !AppSettings.mappingEnabled { showWindow() }
  }

  func applicationDidBecomeActive(_ notification: Notification) { refreshStatus() }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    do {
      try session.restore()
      hotkey.stop()
      return .terminateNow
    } catch {
      showError(error)
      return .terminateCancel
    }
  }

  private func configureMenu() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "⇪"
    statusItem.button?.toolTip = "Caps Switch"
    let menu = NSMenu()
    let settings = NSMenuItem(title: "설정…", action: #selector(showWindow), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)
    toggleMenuItem = NSMenuItem(title: "사용 시작", action: #selector(toggleMapping), keyEquivalent: "")
    toggleMenuItem.target = self
    menu.addItem(toggleMenuItem)
    let reapply = NSMenuItem(
      title: "키보드 연결 후 다시 적용", action: #selector(reapplyMapping), keyEquivalent: "")
    reapply.target = self
    menu.addItem(reapply)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Caps Switch 종료", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    statusItem.menu = menu
  }

  private func configureWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
    )
    window.title = "Caps Switch"
    window.isReleasedWhenClosed = false
    window.center()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    let title = NSTextField(labelWithString: "Caps Lock으로 한영 전환")
    title.font = .systemFont(ofSize: 22, weight: .semibold)
    let description = NSTextField(
      wrappingLabelWithString:
        "Caps Lock을 선택한 펑션 키로 변경합니다. Shift+Caps Lock은 대문자 잠금을 토글합니다. 손쉬운 사용·입력 모니터링 권한을 요청하지 않습니다."
    )
    toggleButton.target = self
    toggleButton.action = #selector(toggleMapping)
    toggleButton.bezelStyle = .rounded
    let heading = NSTextField(labelWithString: "macOS 언어 전환 설정")
    heading.font = .systemFont(ofSize: 15, weight: .semibold)
    keySelector.addItems(withTitles: FunctionKey.allCases.map(\.name))
    keySelector.selectItem(withTitle: session.targetKey.name)
    keySelector.target = self
    keySelector.action = #selector(changeTargetKey)
    let keyLabel = NSTextField(labelWithString: "Caps Lock에 지정할 키 · 변경하면 사용을 중지합니다")
    loginButton.target = self
    loginButton.action = #selector(toggleLoginItem)
    let settings = NSButton(
      title: "키보드 설정 열기", target: self, action: #selector(openKeyboardSettings))
    settings.bezelStyle = .rounded
    let note = NSTextField(
      wrappingLabelWithString:
        "창을 닫아도 메뉴 막대에서 계속 실행합니다. 사용 중지하거나 앱을 종료하면 이 앱이 변경한 Caps Lock 매핑을 복원합니다."
    )
    note.textColor = .secondaryLabelColor
    for view in [
      title, description, keyLabel, keySelector, statusLabel, toggleButton, loginButton, heading,
      guide,
      settings, shortcutLabel, note,
    ] {
      stack.addArrangedSubview(view)
      view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
    }
    guard let content = window.contentView else { return }
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
    ])
  }

  @objc private func showWindow() {
    refreshStatus()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func toggleMapping() {
    do {
      if session.isActive {
        try session.restore()
        hotkey.stop()
        AppSettings.mappingEnabled = false
      } else {
        try enableMapping()
        AppSettings.mappingEnabled = true
      }
    } catch { showError(error) }
    refreshStatus()
  }

  private func enableMapping() throws {
    try hotkey.start(key: session.targetKey)
    do { try session.apply() } catch {
      let applyError = error
      try session.restore()
      hotkey.stop()
      throw applyError
    }
  }

  @objc private func changeTargetKey() {
    guard let selected = keySelector.titleOfSelectedItem,
      let key = FunctionKey.allCases.first(where: { $0.name == selected })
    else { return }
    do {
      try session.restore()
      hotkey.stop()
      AppSettings.mappingEnabled = false
      AppSettings.targetKey = key
      session = MappingSession(targetKey: key)
    } catch { showError(error) }
    keySelector.selectItem(withTitle: session.targetKey.name)
    refreshStatus()
  }

  @objc private func toggleLoginItem() {
    do {
      if loginButton.state == .on {
        try SMAppService.mainApp.register()
        if SMAppService.mainApp.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
        }
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch { showError(error) }
    refreshStatus()
  }

  @objc private func reapplyMapping() {
    guard session.isActive else { return }
    do { try session.apply() } catch { showError(error) }
    refreshStatus()
  }

  @objc private func openKeyboardSettings() {
    let pane = URL(fileURLWithPath: "/System/Library/PreferencePanes/Keyboard.prefPane")
    if !NSWorkspace.shared.open(pane) {
      showError(KeyboardError.failure("키보드 설정을 열지 못했습니다. 시스템 설정에서 키보드를 열어 주세요."))
    }
  }

  @objc private func quit() { NSApp.terminate(nil) }

  private func refreshStatus() {
    let active = session.isActive
    statusLabel.stringValue = active ? "Caps Lock 전환 사용 중" : "Caps Lock 전환 사용 중지"
    toggleButton.title = active ? "사용 중지하고 원래 매핑 복원" : "Caps Lock 전환 사용 시작"
    toggleMenuItem?.title = active ? "사용 중지" : "사용 시작"
    statusItem?.button?.title = active ? "⇪·" : "⇪"
    let keyName = session.targetKey.name
    loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
    guide.stringValue =
      "1. 위 버튼으로 Caps Lock 전환 사용을 시작하세요.\n\n"
      + "2. 시스템 설정 → 키보드 → 텍스트 입력 → 편집에서 ‘Caps Lock으로 입력 소스 전환’을 비활성화하세요.\n\n"
      + "3. 키보드 → 키보드 단축키 → 입력 소스에서 ‘이전 입력 소스 선택’을 활성화하고 단축키를 편집한 뒤 Caps Lock을 누르세요. \(keyName)으로 표시되는지 확인하세요."
    let configured = InputShortcut.isConfigured(for: session.targetKey)
    shortcutLabel.stringValue =
      configured
      ? "이전 입력 소스 선택: \(keyName) 설정 확인"
      : "이전 입력 소스 선택을 \(keyName)으로 설정해 주세요."
    shortcutLabel.textColor = configured ? .systemGreen : .secondaryLabelColor
  }

  private func showError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Caps Switch"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.runModal()
  }
}
