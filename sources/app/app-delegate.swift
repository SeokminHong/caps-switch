import AppKit
import CapsSwitchCore
import ServiceManagement

private final class GuideStackView: NSStackView {
  override var isFlipped: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func checkGuideLayout() throws {
    configureWindow()
    refreshStatus()
    guard let content = window.contentView,
      let scroll = content.subviews.first as? NSScrollView,
      let stack = scroll.documentView as? NSStackView
    else { throw KeyboardError.failure("안내 화면을 찾지 못했습니다.") }
    content.layoutSubtreeIfNeeded()
    stack.layoutSubtreeIfNeeded()
    let images = stack.arrangedSubviews.compactMap { $0 as? NSImageView }
    guard images.count == 2, images.allSatisfy({ $0.image != nil && $0.frame.width > 0 }),
      stack.frame.height > scroll.contentView.bounds.height
    else { throw KeyboardError.failure("안내 이미지 또는 스크롤 영역을 확인하지 못했습니다.") }
    for (index, view) in stack.arrangedSubviews.enumerated() where view is NSImageView {
      guard index > 0,
        let label = stack.arrangedSubviews[index - 1] as? NSTextField,
        label.frame.width > 0,
        label.frame.maxY <= view.frame.minY
      else {
        throw KeyboardError.failure("설명과 안내 이미지의 배치를 확인하지 못했습니다.")
      }
    }
    print("Guide images: \(images.count), content height: \(stack.frame.height)")
  }
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
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Caps Switch"
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 600, height: 500)
    window.center()
    let stack = GuideStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 16
    stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let title = NSTextField(labelWithString: "Caps Lock으로 입력 소스 전환")
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
    let firstStep = NSTextField(
      wrappingLabelWithString:
        "1. 위 버튼으로 Caps Lock 전환 사용을 시작하세요.")
    let capsStep = NSTextField(
      wrappingLabelWithString:
        "2. 시스템 설정 → 키보드 → 텍스트 입력 → 편집… → 모든 입력 소스에서 ‘Caps Lock 키로 ABC 입력 소스 전환’을 비활성화하고 ‘완료’를 클릭하세요."
    )
    let capsImage = guideImage(named: "caps-lock-input-source")
    let shortcutImage = guideImage(named: "input-source-shortcut")
    let imageNote = NSTextField(
      wrappingLabelWithString:
        "위 이미지는 F18 설정 예시입니다. 다른 펑션 키를 선택했다면 해당 키 이름으로 표시되는지 확인하세요.")
    for view in [
      title, description, keyLabel, keySelector, statusLabel, toggleButton, loginButton, heading,
      firstStep, capsStep, capsImage, guide, shortcutImage, imageNote,
      settings, shortcutLabel, note,
    ] {
      stack.addArrangedSubview(view)
      view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -48).isActive =
        true
      if view is NSTextField {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
      }
    }
    for view in [capsImage, shortcutImage] {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
    }
    guard let content = window.contentView else { return }
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(scroll)
    scroll.documentView = stack
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: content.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
    ])
  }

  private func guideImage(named name: String) -> NSImageView {
    let view = NSImageView()
    if let url = Bundle.main.url(forResource: name, withExtension: "png"),
      let image = NSImage(contentsOf: url)
    {
      view.image = image
      view.imageScaling = .scaleProportionallyUpOrDown
      view.setContentHuggingPriority(.defaultLow, for: .horizontal)
      view.setContentHuggingPriority(.defaultLow, for: .vertical)
      view.heightAnchor.constraint(
        equalTo: view.widthAnchor, multiplier: image.size.height / image.size.width
      ).isActive = true
    }
    return view
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
      "3. 키보드 → 키보드 단축키… → 입력 소스에서 ‘이전 입력 소스 선택’을 활성화하세요. 키 조합을 두 번 클릭한 다음 Caps Lock을 누르고 \(keyName)으로 표시되는지 확인하세요. ‘완료’를 클릭하세요."
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
