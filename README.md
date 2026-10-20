# Caps Switch

Caps Lock을 누르는 즉시 한영 전환을 요청하고 Shift+Caps Lock으로 대문자 잠금을 토글하는 macOS 메뉴 막대 앱이다. macOS 14 이상에서 실행한다.

## 사용 방법

1. 앱을 실행하고 메뉴 막대 ‘⇪’ → ‘설정…’ → ‘손쉬운 사용 권한 설정…’을 누른다.
2. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 Caps Switch를 허용한다.

다른 앱으로 이동하면 자동으로 시작한다. macOS의 Caps Lock 입력 소스 전환 옵션이나 키보드 단축키를 직접 설정할 필요가 없다. 권한이 이미 있으면 실행 즉시 저장한 사용 상태를 복원한다. ‘사용 중지’한 상태는 다음 실행에도 유지하며 ‘사용 시작’으로 다시 켤 수 있다.

앱은 설정 창을 열지 않고 메뉴 막대에서 실행한다. 메뉴의 ‘설정…’을 선택하거나 실행 중인 앱을 다시 열면 설정을 표시한다. 다른 앱으로 이동하면 창을 닫고 참조를 해제한다. 창을 닫아도 한영 전환은 계속 동작한다. ‘로그인 시 자동 실행’으로 로그인 항목을 등록할 수 있다.

## 동작과 복원

앱이 Caps Lock을 F키로 매핑하고 macOS의 ‘이전 입력 소스 선택’을 같은 키로 자동 설정한다. 설정의 ‘Caps Lock에 지정할 키’에서 F13~F20을 선택할 수 있으며 기본값은 F18이다. 사용 중에 키를 변경하면 원래 설정을 복원한 뒤 선택한 키로 자동 재설정한다. 사용 중지 상태에서는 키만 저장한다. 선택한 키가 다른 macOS 단축키와 충돌하면 오류를 표시하며 임의로 다른 키로 바꾸지 않는다. 사용자가 설정한 Caps Lock의 기본 입력 소스 전환 옵션은 변경하지 않는다. 키 매핑 이후의 F키 이벤트를 처리하므로 해당 옵션을 수동으로 끌 필요가 없다.

손쉬운 사용 권한으로 첫 키 누름에서 같은 F키의 누름·뗌 이벤트를 연속으로 보낸다. 실제 키 뗌과 반복 입력을 소비해 중복 전환을 막고, Shift+Caps Lock은 대문자 잠금을 토글한다. 입력 소스를 직접 선택하거나 조합 중인 문자열을 수정하지 않는다. 입력 소스가 두 개이면 두 소스를 전환하고, 더 많으면 macOS의 ‘이전 입력 소스 선택’ 동작을 따른다. 입력 소스 설치·삭제나 언어 목록은 변경하지 않는다.

사용 중지·정상 종료 시 원래 Caps Lock 매핑과 단축키를 복원한다. 다른 키의 매핑과 다른 시스템 단축키는 보존한다. 사용자가 이후 직접 수정한 값도 덮어쓰지 않는다. 단축키의 원래 값과 복원 진행 상태를 저장해 재실행 후에도 복원을 재시도한다. 일부 복원이 실패하면 나머지를 계속 처리하고, 종료를 취소해 다시 시도할 수 있다.

연결된 키보드가 없어도 사용 상태를 유지한다. 키보드 하나의 적용 실패로 다른 키보드의 적용을 중단하지 않는다. 절전·화면 복귀, 사용자 세션 복귀, 키보드 서비스 연결 변경 알림으로 매핑을 복구한다. 복귀 직후 서비스가 준비되지 않은 경우를 위해 알림마다 제한된 횟수로 재시도하며 상시 조회 타이머는 사용하지 않는다. 사용 중지 상태에서는 재적용하지 않는다.

손쉬운 사용 권한 상실을 감지하면 이벤트 처리와 매핑을 중지하고 자동 설정한 단축키를 복원한다. 다시 허용한 뒤 다른 앱으로 이동하면 자동으로 시작한다. 권한 확인도 앱 활성화·복귀 알림으로 처리한다.

화면 잠금 해제에는 비공개 `com.apple.screenIsUnlocked` 알림을 보조적으로 참조하며 공개 절전·화면·세션 복귀 및 키보드 연결 알림을 별도로 처리한다. 단축키 자동 설정은 비공개 `com.apple.symbolichotkeys` 형식과 내부 `activateSettings -u -virtualSession` 도구에 의존한다. 지원되지 않는 macOS에서는 오류를 표시하고 변경한 설정을 복원한다.

입력 소스 전환 완료를 기다리거나 후속 글자를 보류하지 않으므로 모든 입력기·앱에서 전환 완료 시간을 보장하지는 않는다. SIGTERM·SIGINT에는 복원하며 SIGKILL·프로세스 충돌에는 매핑이 남을 수 있다. 키 매핑은 재부팅하면 사라지고, 단축키 복원 정보는 다음 실행까지 보관한다.

이벤트 탭은 키 누름·뗌을 수신하지만 선택한 F키만 가공한다. 입력 내용을 저장하거나 전송하지 않는다. 입력 모니터링·관리자 권한, 가상 키보드 드라이버, 네트워크 기능, 외부 패키지는 사용하지 않는다.

## 빌드와 실행

```sh
zsh scripts/build-app.sh
open 'build/Caps Switch.app'
```

## Homebrew 설치

```sh
brew install seokminhong/brew/caps-switch
open "$(brew --prefix caps-switch)/Caps Switch.app"
```

Apple Silicon과 Intel을 지원한다. Bottle이 없으면 Swift 6 이상을 포함한 Xcode 16 이상으로 소스 빌드한다. Finder에서 실행하려면 응용 프로그램 폴더에 연결한다.

```sh
mkdir -p ~/Applications
ln -s "$(brew --prefix)/opt/caps-switch/Caps Switch.app" ~/Applications/
```

소스 릴리스 태그를 기준으로 빌드하며 ad hoc 서명을 사용한다. Developer ID 서명과 Apple 공증은 포함하지 않는다. 앱 업데이트 후 macOS가 손쉬운 사용 권한을 다시 요구할 수 있다. tap 배포는 PR 검증 후 `pr-pull` 워크플로로 진행한다.

## 검증

```sh
xcrun swift test --jobs 2
xcrun swift-format lint --strict --recursive Package.swift sources tests
'build/Caps Switch.app/Contents/MacOS/CapsSwitch' --verify
'build/Caps Switch.app/Contents/MacOS/CapsSwitch' --verify-shortcut
'build/Caps Switch.app/Contents/MacOS/CapsSwitch' --check-guide
```

`--verify`는 연결된 키보드에 Caps Lock → F18을 일시 적용하고 별도 연결로 매핑을 초기화한 뒤 복구·복원을 확인한다. 대문자 잠금 변경·복원과 Shift+F18 등록·해제도 확인한다. `--verify-shortcut`은 실제 단축키의 F18 적용·별도 조회와 전체 설정 복원을 확인한다. 앱 사용을 중지한 상태에서 실행한다. `--check-guide`는 빌드한 앱의 권한 안내와 설정 화면 배치를 확인한다.

실제 키 입력 검증에서는 macOS의 기존 Caps Lock 옵션과 단축키를 그대로 두고 앱에 손쉬운 사용 권한만 허용한다. Caps Lock을 누른 채 다음 글자를 입력하고, 길게 눌러도 전환이 반복되지 않는지와 Shift+Caps Lock 동작을 확인한다. 실제 절전·잠금·재연결 후 복구와 사용 중지 후 미적용도 별도로 확인한다.

## 참고 자료


- [Apple TN2450: 키 매핑 API](https://developer.apple.com/library/archive/technotes/tn2450/)
- [Apple IOHIDSetModifierLockState](https://developer.apple.com/documentation/iokit/1555420-iohidsetmodifierlockstate)
- [Apple 로그인 항목 API](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
