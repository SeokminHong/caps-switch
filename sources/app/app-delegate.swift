import AppKit
import CapsSwitchCore
import Darwin
import ServiceManagement

private final class GuideStackView: NSStackView {
  override var isFlipped: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  func checkGuideLayout() throws {
    configureWindow()
    refreshStatus()
    guard let content = window.contentView,
      let scroll = content.subviews.first as? NSScrollView,
      let stack = scroll.documentView as? NSStackView
    else { throw KeyboardError.failure("설정 화면을 찾지 못했습니다.") }
    content.layoutSubtreeIfNeeded()
    stack.layoutSubtreeIfNeeded()
    guard stack.arrangedSubviews.contains(where: { ($0 as? NSButton)?.title == "손쉬운 사용 권한 설정…" }),
      keySelector.itemTitles == FunctionKey.allCases.map(\.name),
      keySelector.titleOfSelectedItem == session.targetKey.name,
      stack.arrangedSubviews.allSatisfy({ $0.frame.width > 0 }),
      stack.arrangedSubviews.allSatisfy({ !($0 is NSImageView) })
    else { throw KeyboardError.failure("권한 안내와 설정 화면 배치를 확인하지 못했습니다.") }
    print(
      "손쉬운 사용 권한 안내·자동 설정 화면 배치 확인 성공: \(stack.frame.height) / \(scroll.contentView.bounds.height)")
  }
  private let shortcut = InputShortcutSession()
  private lazy var pulse = SwitchPulse { [weak self] error in
    self?.handlePulseFailure(error)
  }

  private var awaitingPermission = false

  private func handlePulseFailure(_ error: Error) {
    awaitingPermission = AppSettings.mappingEnabled
    var errors = [error.localizedDescription]
    do { try stopMapping() } catch { errors.append(error.localizedDescription) }
    mappingError = errors.joined(separator: "\n")
    NSLog("Caps Switch instant switching: %@", mappingError ?? "")
    refreshStatus()
  }

  private var session = MappingSession(targetKey: AppSettings.targetKey)
  private lazy var hotkey = CapsHotkey { [weak self] in
    do { try CapsLock.toggle() } catch { self?.showError(error) }
  }
  private var statusItem: NSStatusItem!
  private var window: NSWindow!
  private static let recoveryDelays: [TimeInterval] = [0.2, 1, 3]
  private var recoveryTasks: [DispatchWorkItem] = []
  private var mappingError: String?
  private var terminationSignals: [DispatchSourceSignal] = []
  private lazy var keyboardObserver = KeyboardServiceObserver { [weak self] in
    self?.scheduleMappingRecovery()
  }
  private let keySelector = NSPopUpButton(frame: .zero, pullsDown: false)
  private let statusLabel = NSTextField(wrappingLabelWithString: "사용 중지")
  private let toggleButton = NSButton(title: "Caps Lock 전환 사용 시작", target: nil, action: nil)
  private var toggleMenuItem: NSMenuItem!
  private let loginButton = NSButton(checkboxWithTitle: "로그인 시 자동 실행", target: nil, action: nil)

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureMenu()
    configureMappingRecovery()
    configureTerminationSignals()
    do {
      if AppSettings.mappingEnabled && SwitchPulse.isTrusted {
        try enableMapping()
      } else {
        try shortcut.restore()
        awaitingPermission = AppSettings.mappingEnabled
      }
    } catch {
      mappingError = error.localizedDescription
      NSLog("Caps Switch startup: %@", error.localizedDescription)
    }
    refreshStatus()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showWindow()
    return true
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    checkPermissionAndResume()
    refreshStatus()
  }

  @objc private func checkPermissionAndResume() {
    if session.isActive && !SwitchPulse.isTrusted {
      handlePulseFailure(KeyboardError.failure("손쉬운 사용 권한이 해제되었습니다. 다시 허용하면 자동으로 시작합니다."))
    } else if awaitingPermission && AppSettings.mappingEnabled && SwitchPulse.isTrusted {
      awaitingPermission = false
      do { try enableMapping() } catch {
        mappingError = error.localizedDescription
        NSLog("Caps Switch activation: %@", error.localizedDescription)
      }
      refreshStatus()
    }
  }

  func applicationDidResignActive(_ notification: Notification) { window?.close() }

  func windowWillClose(_ notification: Notification) {
    (window?.contentView?.subviews.first as? NSScrollView)?.documentView = nil
    window?.contentView = nil
    window = nil
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    do {
      try stopMapping()
      keyboardObserver.stop()
      NSWorkspace.shared.notificationCenter.removeObserver(self)
      DistributedNotificationCenter.default().removeObserver(self)
      return .terminateNow
    } catch {
      showError(error)
      refreshStatus()
      return .terminateCancel
    }
  }

  private func configureTerminationSignals() {
    for number in [SIGTERM, SIGINT] {
      let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
      source.setEventHandler { NSApp.terminate(nil) }
      signal(number, SIG_IGN)
      source.resume()
      terminationSignals.append(source)
    }
  }

  private func configureMappingRecovery() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(checkPermissionAndResume),
      name: NSWorkspace.didActivateApplicationNotification, object: nil)
    for name in [
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      center.addObserver(
        self, selector: #selector(scheduleMappingRecovery), name: name, object: nil)
    }
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(scheduleMappingRecovery),
      name: Notification.Name("com.apple.screenIsUnlocked"), object: nil
    )
    do { try keyboardObserver.start() } catch { showError(error) }
  }

  private func cancelMappingRecovery() {
    for task in recoveryTasks { task.cancel() }
    recoveryTasks.removeAll()
  }

  @objc private func scheduleMappingRecovery() {
    guard session.isActive else { return }
    pulse.reset()
    if !SwitchPulse.isTrusted {
      handlePulseFailure(KeyboardError.failure("손쉬운 사용 권한을 확인한 뒤 다시 시작해 주세요."))
      return
    }
    cancelMappingRecovery()
    for delay in Self.recoveryDelays {
      let task = DispatchWorkItem { [weak self] in self?.recoverMapping() }
      recoveryTasks.append(task)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
  }

  @objc private func recoverMapping() {
    checkPermissionAndResume()
    guard session.isActive else { return }
    do {
      try session.reconcile()
      mappingError = nil
    } catch {
      mappingError = error.localizedDescription
      NSLog("Caps Switch mapping recovery: %@", error.localizedDescription)
    }
    refreshStatus()
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
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Caps Switch"
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.center()
    let stack = GuideStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 20
    stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let title = NSTextField(labelWithString: "Caps Lock으로 한영 전환")
    title.font = .systemFont(ofSize: 22, weight: .semibold)
    let description = NSTextField(
      wrappingLabelWithString:
        "손쉬운 사용에서 Caps Switch만 허용하세요. 권한을 허용한 뒤 다른 앱으로 이동하면 자동으로 시작합니다. macOS 입력기나 키보드 단축키는 직접 설정할 필요가 없습니다."
    )
    let keyLabel = NSTextField(labelWithString: "Caps Lock에 지정할 키")
    keySelector.removeAllItems()
    keySelector.addItems(withTitles: FunctionKey.allCases.map(\.name))
    keySelector.selectItem(withTitle: session.targetKey.name)
    keySelector.target = self
    keySelector.action = #selector(changeTargetKey)
    let permission = NSButton(
      title: "손쉬운 사용 권한 설정…", target: self, action: #selector(openAccessibilitySettings))
    permission.bezelStyle = .rounded
    toggleButton.target = self
    toggleButton.action = #selector(toggleMapping)
    toggleButton.bezelStyle = .rounded
    loginButton.target = self
    loginButton.action = #selector(toggleLoginItem)
    let note = NSTextField(
      wrappingLabelWithString:
        "Caps Lock을 누르는 즉시 언어 전환을 요청합니다. Shift+Caps Lock은 대문자 잠금을 켜거나 끕니다. 사용 중지하거나 종료하면 원래 매핑과 단축키를 복원합니다."
    )
    note.textColor = .secondaryLabelColor
    for view in [
      title, description, keyLabel, keySelector, permission, statusLabel, toggleButton, loginButton,
      note,
    ] {
      stack.addArrangedSubview(view)
      view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -48).isActive =
        true
      if view is NSTextField {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
      }
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

  @objc private func showWindow() {
    if window == nil { configureWindow() }
    refreshStatus()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func toggleMapping() {
    do {
      if session.isActive || awaitingPermission || session.hasPendingRestoration
        || shortcut.hasPendingRestoration
      {
        awaitingPermission = false
        AppSettings.mappingEnabled = false
        try stopMapping()
      } else {
        AppSettings.mappingEnabled = true
        if !SwitchPulse.isTrusted {
          awaitingPermission = true
          openAccessibilitySettings()
        } else {
          try enableMapping()
        }
      }
    } catch { showError(error) }
    refreshStatus()
  }

  private func stopMapping() throws {
    cancelMappingRecovery()
    pulse.stop()
    hotkey.stop()
    var failures: [String] = []
    do { try session.restore() } catch { failures.append(error.localizedDescription) }
    do { try shortcut.restore() } catch { failures.append(error.localizedDescription) }
    guard failures.isEmpty else { throw KeyboardError.failure(failures.joined(separator: "\n")) }
    mappingError = nil
  }

  private func enableMapping() throws {
    do {
      if !SwitchPulse.isTrusted {
        throw KeyboardError.failure("손쉬운 사용에서 Caps Switch를 허용한 뒤 사용을 시작해 주세요.")
      }
      let key = AppSettings.targetKey
      if key != session.targetKey {
        try session.restore()
        session = MappingSession(targetKey: key)
      }
      try shortcut.apply(key: key)
      AppSettings.targetKey = key
      try hotkey.start(key: session.targetKey)
      try pulse.start(key: session.targetKey)
      do { try session.apply() } catch {
        if !session.isActive { throw error }
        mappingError = error.localizedDescription
        NSLog("Caps Switch mapping pending: %@", error.localizedDescription)
        scheduleMappingRecovery()
        return
      }
    } catch {
      let original = error
      do { try stopMapping() } catch {
        throw KeyboardError.failure(
          "\(original.localizedDescription)\n복원 실패: \(error.localizedDescription)")
      }
      throw original
    }
    mappingError = nil
    scheduleMappingRecovery()
  }

  @objc private func changeTargetKey() {
    guard let name = keySelector.titleOfSelectedItem,
      let key = FunctionKey.allCases.first(where: { $0.name == name }),
      key != session.targetKey
    else { return }
    let resume = AppSettings.mappingEnabled
    do {
      awaitingPermission = false
      try stopMapping()
      AppSettings.targetKey = key
      session = MappingSession(targetKey: key)
      if resume {
        if SwitchPulse.isTrusted { try enableMapping() } else { awaitingPermission = true }
      }
    } catch {
      mappingError = error.localizedDescription
      showError(error)
    }
    refreshStatus()
  }

  @objc private func openAccessibilitySettings() {
    if !session.isActive {
      AppSettings.mappingEnabled = true
      awaitingPermission = true
    }
    checkPermissionAndResume()
    SwitchPulse.requestPermission()
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
      NSWorkspace.shared.open(url)
    else {
      showError(KeyboardError.failure("손쉬운 사용 설정을 열지 못했습니다."))
      return
    }
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
    checkPermissionAndResume()
    guard session.isActive else { return }
    do {
      try session.apply()
      mappingError = nil
    } catch {
      mappingError = error.localizedDescription
      NSLog("Caps Switch mapping pending: %@", error.localizedDescription)
    }
    scheduleMappingRecovery()
    refreshStatus()
  }

  @objc private func quit() { NSApp.terminate(nil) }

  private func refreshStatus() {
    let active = session.isActive
    keySelector.selectItem(withTitle: session.targetKey.name)
    statusLabel.stringValue = active ? "한영 전환 사용 중" : "사용 중지"
    if awaitingPermission { statusLabel.stringValue = "손쉬운 사용 권한을 허용하면 자동으로 시작합니다." }
    if let mappingError { statusLabel.stringValue += "\n\(mappingError)" }
    if !active && (session.hasPendingRestoration || shortcut.hasPendingRestoration) {
      statusLabel.stringValue = "원래 설정 복원 대기 · 사용 중지 버튼으로 다시 시도해 주세요."
      if let mappingError { statusLabel.stringValue += "\n\(mappingError)" }
    }
    let needsStop =
      active || awaitingPermission || session.hasPendingRestoration
      || shortcut.hasPendingRestoration
    toggleButton.title = needsStop ? "사용 중지" : "한영 전환 사용 시작"
    toggleMenuItem?.title = needsStop ? "사용 중지" : "사용 시작"
    statusItem?.button?.title = active ? "⇪·" : "⇪"
    loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }

  private func showError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Caps Switch"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.runModal()
  }
}
