# OneButton 검증 기록

## 0.2.0 추가 검증 (2026-11-07)

- 목록/격자 3열 전환, 보기 설정 저장, 48pt 파일 아이콘, 방향키 이동을 추가했습니다.
- Sparkle 2.10.1을 고정하고 자동 확인·다운로드·설치 옵션, 수동 확인, 메뉴 막대 업데이트 알림을 연결했습니다.
- 단위 테스트 **12개 통과, 실패 0개**: 기존 6개 + 격자 이동 4개 + 업데이터 비활성화/알림 상태 2개. 결과: `.test-artifacts/grid-sparkle-final-unit.xcresult`.
- Debug 임시 서명 빌드와 Release Universal 아카이브·Developer ID 내보내기가 성공했습니다.
- 실제 UI 검증에서 격자 방향키 입력이 전달되지 않는 문제를 재현했고, 격자 ScrollView의 포커스와 이동 명령 처리를 연결한 후 전체 시나리오가 통과했습니다.
- 격자 3열 배치, 방향키/Return, 아이콘 한 번 클릭, 폴더/텍스트 문서 열기, 재실행 후 북마크와 격자 설정 복원, 목록 복귀, 다른 앱의 전체 화면 위에서 격자 열기·닫기를 확인했습니다. 결과: `.test-artifacts/grid-native-ui-smoke-3.log`.
- Release 앱과 Sparkle의 framework, Installer.xpc, Updater.app, Autoupdate 서명 무결성을 확인했습니다. Developer ID, hardened runtime, arm64/x86_64를 포함합니다. 배포본에는 Debug의 library-validation 예외나 파일 쓰기 권한이 없습니다.
- ZIP·DMG 초안은 `dist/pending-notarization/`에 생성했습니다. DMG 이미지 체크섬 검증이 통과했습니다.
- 공증은 `OneButtonNotary` 키체인 프로필 설정 대기 상태입니다. 완료 전 초안은 업데이트 피드에 등록하지 않습니다. 현재 `appcast.xml`은 유효한 빈 피드입니다.
- 공개 GitHub raw feed를 인증 없이 내려받아 저장소 파일과 일치하는지 확인했습니다. Developer ID Release 앱의 **업데이트 → 업데이트 확인…**을 실제로 눌러 Sparkle의 **최신 버전입니다.** 안내를 확인했습니다. 아직 최신 릴리스가 없는 빈 피드 확인이며, 버전 교체 설치 테스트와는 다릅니다. 결과: `.test-artifacts/sparkle-ui-smoke.log`.
- 비공개 테스트 폴더에서 현재 ZIP의 appcast 생성, 버전/URL/크기 검증, 키체인 공개키와 앱 공개키 일치, Sparkle `sign_update --verify`의 EdDSA 검증이 통과했습니다. 최종 공증 후 ZIP을 다시 만들면 반드시 서명과 검증을 다시 수행해야 합니다.
- 잘못된 다운로드 URL과 파일 크기를 넣은 피드를 `PYTHONOPTIMIZE=1`에서도 거부하는 음성 테스트가 통과했습니다.
- 저장소: `https://github.com/mindw96/DesktopButton`, 구현 커밋 `7c57eb3`, `main` 푸시 완료. 공증된 릴리스와 업데이트 enclosure는 아직 공개하지 않았습니다.

공증·Gatekeeper 설치·Sparkle 실제 버전 교체의 완료 여부는 아래 배포 기록에 별도로 기록합니다. 아래 항목은 0.1.0 초기 구현의 검증 기록입니다.

검증일: 2026-11-07 (Asia/Seoul)

## 환경

- MacBook Pro / Apple Silicon, macOS 27.2 (26B7124)
- Xcode 27.2 (27B52), Swift 6.4.2 컴파일러 / Swift 5 언어 모드
- 앱 배포 대상 macOS 13.0, 현재 Xcode의 XCTest 실행 대상 macOS 14.0 이상
- 로컬 임시 서명, App Sandbox 활성화
- 단일 내장 디스플레이, 논리 해상도 1800 × 1169

## 빌드와 단위 테스트

| 항목 | 결과 |
| --- | --- |
| Debug 앱 빌드 및 프로세스 실행 | 통과 |
| Release 앱 빌드 | 통과 |
| Info.plist 및 entitlements 형식 | 통과 |
| 로컬 앱 코드 서명 무결성 | 통과 |
| 단위 테스트 | 6개 통과, 실패 0개 |

단위 테스트는 실제 임시 파일로 얕은 조회·숨김 제외·자연 정렬·패키지 처리를 확인하고, 없는 폴더의 실패, 미연결/빈 폴더/오류 구분, 오래된 비동기 결과 차단, 손상된 북마크, 현재 목록 밖의 열기 요청과 오류 보존을 검사합니다.

단위 테스트 결과 번들: `.test-artifacts/final-unit.xcresult`.

## 실제 UI 검증

`script/ui_smoke.swift`는 OneButton의 테스트 설정과 임시 폴더로 실제 메뉴·폴더 선택 창을 조작합니다. 메뉴 막대에서 관측한 컨트롤 위치를 사용하고, 앱 내부 화면은 해당 프로세스의 접근성 트리로 확인합니다. 화면 캡처는 OneButton 자신의 팝업 창에 한정합니다.

| 시나리오 | 결과 |
| --- | --- |
| 첫 실행 연결 안내 표시 | 통과 |
| 메뉴 열기 → Esc 닫기 → 재열기 | 통과 |
| 표준 폴더 선택 창으로 임시 폴더 접근 허용 | 통과 |
| 선택한 폴더의 파일 표시, 숨김 파일 제외 | 통과 |
| Return으로 선택한 폴더를 Finder에서 열기 | 통과 |
| 행 클릭으로 폴더를 Finder에서 열기 | 통과 |
| 텍스트 파일을 기본 앱인 TextEdit에서 열기 | 통과 |
| 팝업 한 번 클릭 재개방 시 파일 추가 반영 | 통과 |
| 앱 재실행 후 보안 범위 북마크 복원 | 통과 |
| 다른 앱의 전체 화면 위에서 팝업 열기·닫기 | 통과 |

전체 화면 검증은 별도 `OneButtonFullscreenFixture` 앱이 실제 전체 화면에 진입한 뒤 수행했습니다. 팝업이 열린 동안과 닫힌 후에 테스트 앱의 창이 현재 화면에 남아 있는지 확인했고, 열린 팝업도 실제 화면에 표시되어 있는지 Window Server 정보로 확인했습니다. 다른 앱·OS·다중 모니터 조합 전체를 검증했다는 뜻은 아닙니다.

캡처 파일: `.test-artifacts/native-first-launch.png`, `.test-artifacts/native-connected.png`, `.test-artifacts/native-fullscreen-popup.png`. 표시된 파일은 테스트 데이터입니다.

UI 실행 결과는 `.test-artifacts/native-ui-smoke.log`에 기록했습니다. 전체 흐름 통과 뒤 검증 스크립트의 진단용 로그와 추가 클릭을 제거하고 타입 검사를 했습니다. 중복 실행을 방지하는 사전 조건도 추가했습니다. 제품 코드에는 이 정리로 인한 변경이 없습니다.

### 최종 메뉴 막대 구현 선택

SwiftUI `MenuBarExtra` 시제품에서 폴더 연결 이후 닫기와 내부 표시 상태가 어긋나, 다시 열려면 아이콘을 두 번 눌러야 하는 문제를 실제 화면에서 재현했습니다. 계획의 대안대로 메뉴 막대 부분을 `NSStatusItem + NSPopover`로 전환했습니다. 표시 상태와 닫기는 `NSPopover`가 소유하며, 목록 갱신은 `popoverDidShow`에서 시작합니다. 파일 목록 UI와 파일 접근 코드는 재사용했습니다. 위 UI 결과는 전환 후 한 번 클릭으로 수행한 검증입니다.

현재 macOS의 메뉴 막대는 새 아이콘을 접힌 영역에 넣을 수 있습니다. OneButton 아이콘이 보이지 않으면 메뉴 막대의 겹화살표로 **가려진 메뉴 막대 항목 보기**를 펼쳐야 합니다. 앱에서 이 시스템 표시 설정을 강제로 바꾸지 않습니다.

## 확인하지 않은 범위

- iCloud의 클라우드 전용 파일, 오프라인 다운로드 실패, 제3자 동기화 서비스.
- macOS 13–26 실제 실행, Intel Mac, 다중 모니터 및 Spaces 설정별 조합.
- VoiceOver 음성 출력의 직접 청취. 접근성 레이블과 키보드 동작은 별도로 점검합니다.
- 실제 사용자 바탕화면 파일의 변경·삭제 테스트. 테스트는 임시 폴더만 사용합니다.
- 배포용 서명·공증, Gatekeeper 다운로드 설치, App Store 제출.

외부 앱에서 파일을 연 뒤 표시되는 Space는 대상 앱과 macOS 설정의 영향을 받습니다. 검증한 전체 화면 유지 동작은 목록을 열고 닫는 단계입니다.
