# Caps Switch

Caps Lock을 F18로 변경하고 Shift+Caps Lock으로 대문자 잠금을 토글하는 macOS 메뉴 막대 앱이다. macOS 14 이상에서 실행한다.

손쉬운 사용·입력 모니터링·관리자 권한을 요청하지 않는다. 키 입력 전체를 수신하는 이벤트 감시기, 가상 키보드 드라이버, 네트워크 기능, 외부 패키지를 추가하지 않는다. macOS의 키 매핑 API와 Shift+F18 전역 단축키를 사용한다.

## 빌드와 실행

```sh
cd /Users/seokmin/Documents/personal/caps-switch
zsh scripts/build-app.sh
open '/Users/seokmin/Documents/personal/caps-switch/build/Caps Switch.app'
```

앱에서 ‘Caps Lock 전환 사용 시작’을 누른다. 처음 실행할 때는 키 매핑을 변경하지 않는다.

## 언어 전환 설정

앱의 ‘키보드 설정 열기’ 버튼으로 macOS 설정을 연다. 텍스트 입력의 편집 화면에서 Caps Lock으로 입력 소스를 전환하는 옵션을 비활성화한다. 키보드 단축키의 입력 소스에서 ‘이전 입력 소스 선택’을 활성화하고 단축키를 편집하면서 Caps Lock을 눌러 F18로 등록한다.

앱은 언어 전환 설정을 안내하고 F18 등록 상태를 조회한다. macOS의 비공개 설정 형식에는 값을 기록하지 않는다. 한글과 영어만 등록하면 F18로 두 입력 소스를 전환할 수 있다.

## 실행과 복원

설정 창을 닫아도 앱은 메뉴 막대에서 계속 실행한다. ‘사용 중지’하거나 앱을 정상 종료하면 Caps Lock의 이전 매핑을 복원한다. 다른 키의 매핑은 보존한다. 새로운 키보드를 연결하면 메뉴의 ‘키보드 연결 후 다시 적용’을 누른다.

Shift+Caps Lock 토글은 앱이 실행 중일 때 동작한다. 강제 종료하면 macOS에 적용한 F18 매핑은 남을 수 있으며 재부팅하면 사라진다. 자동 로그인 실행은 등록하지 않으므로 재부팅 후 앱을 직접 실행한다. macOS에서 등록한 F18 언어 전환 단축키는 앱 종료 후에도 유지한다.

## 검증

```sh
xcrun swift test --jobs 2
xcrun swift-format lint --strict --recursive Package.swift sources tests
'build/Caps Switch.app/Contents/MacOS/CapsSwitch' --verify
```

`--verify`는 연결된 키보드에 Caps Lock → F18을 일시 적용한 뒤 조회하고, 대문자 잠금 상태를 변경한 뒤 원래 상태로 복원한다. Shift+F18 등록·해제도 확인한다. 물리 키 입력과 입력 소스 전환은 앱의 설정을 마친 뒤 직접 확인한다.

## 참고 자료

- [Apple TN2450: 키 매핑 API](https://developer.apple.com/library/archive/technotes/tn2450/)
- [Apple IOHIDSetModifierLockState](https://developer.apple.com/documentation/iokit/1555420-iohidsetmodifierlockstate)
