# Folder In Bar 검증 기록

## 0.3.0 폴더인바 이름과 앱 아이콘 (2026-11-11)

새 이름은 **폴더인바(Folder In Bar)**, 버전 **0.3.0 (build 5)**입니다. 앱 표시 이름·실행 파일·신규 설치 번들·메뉴 안내를 변경하고, 파란 폴더와 메뉴 막대를 결합한 아이콘을 추가했습니다. macOS AppIcon 10개 표현(16–1024px)을 빌드에 포함했습니다. 생성 원본과 프롬프트는 `docs/branding/`에 있습니다.

기존 bundle ID·서명 Team·Sparkle 키/피드·설정 키·메뉴 위치 식별자는 유지했습니다. Xcode 프로젝트/scheme/Swift 모듈은 내부 이름 `OneButton`을 유지하되 productName과 테스트 호스트·실행 scheme의 실제 앱 경로는 새 이름을 사용합니다.

- **단위 테스트 23개 통과, 실패 0개, 런타임 경고 0개**. 작업 공간에서 첫 XCTest 실행이 dyld의 라이브러리 열기 단계에 머물러 중단했습니다. 제품 소스·테스트·리소스·프로젝트 해시가 같은 `/private/tmp` 전체 복사본에서 다시 실행해 통과했습니다. 정확한 대기 원인은 단정하지 않습니다. 결과: `.test-artifacts/rename-icon-unit-local.xcresult`.
- 실제 UI에서 새 앱 metadata·안내 이름, 설정 메뉴, 폴더 연결·열기, 목록·격자 전환, 방향키, 크기 조절·재실행 복원, 전체화면 유지가 통과했습니다. 테스트 앱의 시작 완료를 기다려 명시적으로 활성화하도록 검사 스크립트를 보완했습니다. 결과: `.test-artifacts/rename-icon-ui-2.log`.
- Release Universal archive/export, 코드 서명·Release 권한·Gatekeeper, 앱과 DMG 공증·staple, Sparkle EdDSA 검증이 통과했습니다. 앱 공증 `637182fd-5797-4d32-aeb3-4db9e9628fbf`, DMG 공증 `7e35b0e5-a997-4d63-8331-2faf4987a2e5` — 모두 `Accepted`, issues 없음.
- ZIP과 DMG의 앱 실행 파일·Info.plist·AppIcon.icns가 일치하며 Applications 바로가기를 확인했습니다. 배포 로그: `.test-artifacts/release-0.3.0.log`.

```text
3e951afe4db7f27b3b13fa68ab460c0a3a37e46c20e4f07cf43a630de53b9fbe  FolderInBar-0.3.0.zip
1d6b4b51a82a9eeb77fa91d35ebd54ea66602de8498d5e3ba502130713a97c89  FolderInBar-0.3.0.dmg
```

공개 다운로드와 기존 OneButton의 실제 업데이트 결과는 배포 완료 후 추가합니다. Sparkle 기본 설치 방식은 기존 설치 경로를 유지하므로 자동 업데이트 후 실제 `.app` 파일명은 `OneButton.app`으로 남을 수 있습니다. 새 DMG/ZIP의 앱은 `Folder In Bar.app`입니다.

## 0.2.2 로그인 시 자동 실행 (2026-11-11)

버전 **0.2.2 (build 4)**에 하단 설정 메뉴와 **로그인 시 자동 실행** 옵션을 추가했습니다. `SMAppService.mainApp`으로 등록·해제하고 시스템 상태를 직접 표시합니다. 승인 대기는 활성화와 구분해 안내하며, 시스템 설정으로 이동하거나 등록을 취소할 수 있습니다. 앱 시작·팝업 열기·재활성화 때 상태를 갱신합니다. 앱을 설치하거나 시작하는 것만으로 등록하지 않습니다.

- 단위 테스트 **23개 통과, 실패 0개, 런타임 경고 0개**. 등록·해제, 승인 대기 취소, 등록·해제 오류, 외부 상태 갱신, 테스트 모드의 시스템 접근 차단을 검사하는 6개 테스트를 추가했습니다. 결과: `.test-artifacts/login-item-unit.xcresult`.
- Developer ID 서명된 최종 앱의 실제 설정 메뉴에서 **미등록 → 등록·활성화 → 앱 재실행 후 활성화 유지 → 해제**를 확인했습니다. 시스템 API의 조회 결과로 표시되는 체크와 승인 대기 여부를 대조했으며 원래의 미등록 상태로 복원했습니다. 새 helper·LaunchAgent·entitlement는 추가하지 않았습니다.
- 재실행 직후 메뉴 자동화가 항목을 찾지 못한 경우에는 해당 앱을 활성화한 뒤 확인했습니다. 실제 등록·해제 결과: `.test-artifacts/login-item-release-smoke.log`, `login-item-release-verify.log`, `login-item-release-result.json`.
- 실제 Mac 재시작·로그아웃은 실행하지 않았습니다. 로그인 항목 등록과 앱 재실행을 통한 유지 확인은 실제 재로그인 검증과 구분합니다.
- Universal Release archive/export, 코드 서명과 Release 권한, 앱·DMG 공증·staple, 앱 Gatekeeper, 최종 ZIP의 Sparkle EdDSA 검증이 통과했습니다. 로그: `.test-artifacts/release-0.2.2.log`.
- 앱 공증: `f0a77852-0d91-4bed-8868-f1ae5a1daea3`, DMG 공증: `5cefc60f-c088-49a8-a35b-4c9a9ad4fbe7`. 모두 `Accepted`, issues 없음.

```text
ca4f8fc68b76249ac2c1ccbd5d16c91bd1be390e236bcc91a4ee4bd3e2ba4db4  OneButton-0.2.2.zip
a77f24a37e6cb7f61df2f809fcad331a681458117dc345cdfdfdf0f304f0e86a  OneButton-0.2.2.dmg
```

실제 UI 회귀 검사도 통과했습니다. 새 설정 메뉴와 테스트 모드의 로그인 항목 변경 차단, 폴더 선택·파일 열기, 목록·격자 전환, 키보드 이동, 팝업 크기 조절·재실행 복원, 다른 앱 전체화면 위에서 열기·크기 조절·닫기를 확인했습니다. 초기 메뉴 탐색 실패는 테스트 시작·재실행 시 테스트 앱을 활성화하도록 보완한 뒤 해결했습니다. 결과: `.test-artifacts/login-item-ui-3.log`.

[GitHub Release v0.2.2](https://github.com/mindw96/DesktopButton/releases/tag/v0.2.2)을 공개했습니다. 릴리스 소스 커밋은 `d6428c5`입니다. ZIP·DMG·SHA256SUMS를 인증 없이 다시 내려받아 로컬 최종본과 일치하는지 확인했습니다. 공개 ZIP 앱의 코드 서명·staple·Gatekeeper(`accepted / Notarized Developer ID`)와 공개 DMG의 staple도 통과했습니다. ZIP과 DMG의 앱 실행 파일·Info.plist 및 Applications 바로가기도 대조했습니다.

공개 Sparkle 피드(`7533563`)를 인증 없이 읽어 저장소 파일과 일치하는지 확인했습니다. build 4, 0.2.2, 최소 OS, 공개 ZIP URL·크기를 대조했고 공개 ZIP의 EdDSA 서명 검증이 통과했습니다. 공개 ZIP에서 꺼낸 0.2.2 앱의 **앱 업데이트 확인… → 최신 버전입니다.** 표시도 실제로 확인했습니다. 결과: `.test-artifacts/update-0.2.2-smoke.log`.

실제 재로그인·Mac 재시작, Intel Mac과 macOS 13–26의 실행은 검증하지 않았습니다. 이번 버전의 구버전 교체 설치를 반복하지 않았으며, 이전 0.2.0 → 0.2.1 교체 설치 결과는 아래 기록에 있습니다.

## 0.2.1 폴더 표시와 팝업 크기 조절 (2026-11-11)

버전 **0.2.1 (build 3)**입니다. 연결 안내를 폴더 기준으로 바꾸고, 상단에 연결된 폴더명을 표시합니다. 하단 모서리의 드래그로 팝업 폭·높이를 조절하며, 크기를 저장하고 화면 범위 안으로 제한합니다. 격자 열 수와 방향키 이동이 현재 폭을 따릅니다. 앱 업데이트 메뉴는 11pt 텍스트로 줄이고 별도 아이콘을 제거했습니다.

- 단위 테스트 **17개 통과, 실패 0개, 런타임 경고 0개**. 기존 12개에 크기 저장·복원, 최소·최대·화면 제한, 비정상 크기, 양쪽 모서리 드래그, 가변 격자 이동 검사를 추가했습니다. 결과: `.test-artifacts/folder-resize-unit.xcresult`.
- 실제 폴더 선택창 연결, 폴더명 표시, 목록·격자 전환, 방향키·Return, 폴더와 텍스트 문서 열기, 숨김 제외 및 다시 열 때 갱신을 확인했습니다.
- 실제 포인터 드래그로 폭·높이를 함께 늘리고 줄였으며, 3열에서 4열로 바뀌는 배치를 확인했습니다. 앱 재실행 후 북마크·폴더명·보기 모드·크기 복원이 통과했습니다.
- 전체화면 테스트 앱 위에서 팝업 열기, 격자 전환, 크기 조절, Esc 닫기를 실행하고 현재 전체화면 Space가 유지되는 것을 확인했습니다.
- 드래그 후 예전 크기에 남아 있던 기본 포커스 테두리는 드래그 중 포커스를 해제하고 종료 시 복구하도록 수정했습니다. 최종 캡처에서 정상 표시를 확인했습니다.
- UI 결과: `.test-artifacts/folder-resize-ui-4.log`. 테스트 임시 폴더만 사용했으며 캡처는 `docs/screenshots/`에 반영했습니다.
- 환경: Apple Silicon, macOS 27.2, Xcode 27.2, 주 화면 1920×1080 및 좌우 외부 화면이 연결된 구성. 모든 모니터·Spaces 설정 조합을 검사한 것은 아닙니다.

Release Universal archive와 Developer ID export가 통과했습니다. 앱과 DMG 공증 결과는 모두 `Accepted`, issues 없음이며 staple·validate 및 앱 Gatekeeper 검증을 통과했습니다. Sparkle 공개키 대조, 피드 metadata, 최종 ZIP의 EdDSA 검증도 통과했습니다.

- 앱 공증: `eb039ba1-e3ef-4f53-8a1a-79474f87944c`
- DMG 공증: `2abce756-d85a-4657-94bb-d5b739c9cb25`
- 최종 빌드·공증 로그: `.test-artifacts/release-0.2.1-final.log`

```text
fce0a80fdd6166e5f5173e3f2541b19891bc29ef9258f031b09d15a5bc95da9f  OneButton-0.2.1.zip
e95192885bca4b439a42c6090e0c5975c5aade0d40837780c949d5672825db00  OneButton-0.2.1.dmg
```

[GitHub Release v0.2.1](https://github.com/mindw96/DesktopButton/releases/tag/v0.2.1)을 공개했습니다. 릴리스 소스 커밋은 `77c96a8`입니다. ZIP·DMG·SHA256SUMS를 인증 없이 재다운로드하여 로컬 최종본과 byte 단위 및 SHA-256 일치를 확인했습니다. 공개 ZIP 앱의 코드 서명·staple·Gatekeeper(`accepted / Notarized Developer ID`)와 공개 DMG의 staple 검증도 통과했습니다. ZIP과 DMG의 실행 파일·Info.plist 일치 및 Applications 바로가기를 확인했습니다.

공개 Sparkle 피드(`12c9e48`)를 인증 없이 읽어 저장소 파일과 일치하는지 확인했습니다. build 3, 버전 0.2.1, 최소 OS, 공개 ZIP URL·크기를 대조하고 공개 ZIP의 EdDSA 서명을 실제 검증했습니다.

**실제 0.2.0 → 0.2.1 업데이트 설치도 통과했습니다.** 원래 공개 ZIP의 SHA-256을 대조한 뒤 별도의 `build/upgrade-0.2.1/OneButton.app` 복사본에서 수동 업데이트를 실행했습니다. 공개 피드의 0.2.1 안내 → 다운로드 → 설치 및 재실행을 거쳤고, 이전 PID `82326` 종료와 같은 앱·실행 파일 경로의 새 PID `82358`, 디스크의 `0.2.1 / build 3`을 확인했습니다. 업데이트된 앱의 실행 파일·Info.plist가 공개 ZIP과 일치하며 코드 서명·staple·Gatekeeper 검증도 통과했습니다. 새 팝업의 폴더명·크기 조절 컨트롤과 **앱 업데이트 확인… → 최신 버전입니다.** 표시를 확인했습니다.

재실행 버튼 직후 접근성 응답은 기존 프로세스 종료로 끊겼습니다. 이를 제품 실패로 판단하지 않고 별도의 검증으로 실제 교체·재실행을 확인했습니다. 근거: `.test-artifacts/upgrade-0.2.1-run.log`, `upgrade-0.2.1-verify.log`, `upgrade-0.2.1-verified.json`. 사용자 설치 경로를 덮어쓰지 않았으며 테스트 복사본만 종료했습니다.

미검증 범위: Intel Mac 및 macOS 13–26의 실제 실행, 모든 모니터·Spaces 조합, VoiceOver 음성 출력, iCloud 클라우드 전용 파일. 앱 배포 대상은 macOS 13 이상이며 Universal 바이너리를 제공합니다.

## 0.2.0 공증 및 배포 완료 (2026-11-10)

**[GitHub Release v0.2.0](https://github.com/mindw96/DesktopButton/releases/tag/v0.2.0)**를 공개했습니다. macOS 13 이상, Universal `arm64 + x86_64`, 앱 버전 `0.2.0`, build `2`입니다. 아래 11월 7일의 공증 대기 상태는 이 기록으로 갱신합니다.

| 검증 | 결과 |
| --- | --- |
| Release archive 및 Developer ID export | 통과 — Xcode 27.2 (27B52), macOS 27.2 |
| 앱 및 Sparkle framework·helper·XPC 서명 | 통과 — Team `4J7HGK26PF`, hardened runtime |
| Release 권한 | 읽기 전용 폴더·북마크·네트워크·Sparkle mach lookup, Debug 예외 없음 |
| 앱 공증 | `Accepted`, issues 없음 — `cfd458ad-87fb-47c2-aff4-46cb5ccbfb5d` |
| DMG 공증 | `Accepted`, issues 없음 — `92dcb0c0-1f05-4332-afc6-356ae15a9566` |
| 앱·DMG 공증 티켓 | staple 및 validate 통과 |
| Gatekeeper | 앱 및 공개 ZIP에서 꺼낸 앱 모두 `accepted / Notarized Developer ID` |
| 패키지 구성 | ZIP과 DMG의 앱 실행 파일 일치, DMG의 Applications 바로가기 확인 |
| 공개 파일 검증 | 인증 없는 재다운로드 성공, ZIP·DMG·SHA256SUMS가 로컬 최종본과 일치 |
| Sparkle 서명 | 앱 공개키와 Keychain 공개키 일치, 공개 ZIP의 EdDSA 실제 검증 통과 |
| 공개 업데이트 피드 | raw URL의 내용 일치, build·버전·최소 OS·URL·파일 크기 대조 통과 |
| 배포 앱의 업데이트 UI | 공개 ZIP에서 꺼낸 앱으로 수동 확인, “최신 버전입니다.” 표시 통과 |

최종 파일과 SHA-256:

```text
173edf4c2f047f15cd4e50e93a65e0aa18ab5484bdc16dd3e0a2294899c3b33c  OneButton-0.2.0.zip
6a3b6c71d9320146ed6932c5e410f2257c30cbb3294b9855ce4df45e188f84c2  OneButton-0.2.0.dmg
```

릴리스 태그 `v0.2.0`의 소스 커밋은 `222d842`, 업데이트 피드 공개 커밋은 `eca256d`입니다. 이번 작업에서는 제품 코드를 변경하지 않았으며, 기존 단위 테스트 12개와 실제 UI 검증 결과는 아래에 기록되어 있습니다. 배포 스크립트의 아키텍처 검사를 `lipo -archs` 출력 검사로 보완하고 실제 배포본에서 통과를 확인했습니다.

최종 산출물은 `dist/OneButton-0.2.0.zip`, `dist/OneButton-0.2.0.dmg`, `dist/SHA256SUMS`, `dist/appcast.xml`입니다. `dist/pending-notarization/`은 11월 7일의 미공증 초안이며 배포에 사용하지 않았습니다. 실행 로그는 `.test-artifacts/release-20261110-final.log`, Apple 공증 로그는 `.test-artifacts/notary-app-20261110.json` 및 `notary-dmg-20261110.json`, 업데이트 UI 결과는 `.test-artifacts/sparkle-release-ui-20261110.log`에 있습니다.

실제 구버전 → 신버전 교체 설치, Intel Mac 및 macOS 13–26의 실제 실행은 검증하지 않았습니다. 이번 검증은 최종 패키지·공개 다운로드·Sparkle 피드와 수동 업데이트 확인까지입니다. App Store 제출은 이번 배포 범위에 포함하지 않습니다.

## 0.2.0 추가 검증 (2026-11-07)

- 목록/격자 3열 전환, 보기 설정 저장, 48pt 파일 아이콘, 방향키 이동을 추가했습니다.
- Sparkle 2.10.1을 고정하고 자동 확인·다운로드·설치 옵션, 수동 확인, 메뉴 막대 업데이트 알림을 연결했습니다.
- 단위 테스트 **12개 통과, 실패 0개**: 기존 6개 + 격자 이동 4개 + 업데이터 비활성화/알림 상태 2개. 결과: `.test-artifacts/grid-sparkle-final-unit.xcresult`.
- Debug 임시 서명 빌드와 Release Universal 아카이브·Developer ID 내보내기가 성공했습니다.
- 실제 UI 검증에서 격자 방향키 입력이 전달되지 않는 문제를 재현했고, 격자 ScrollView의 포커스와 이동 명령 처리를 연결한 후 전체 시나리오가 통과했습니다.
- 격자 3열 배치, 방향키/Return, 아이콘 한 번 클릭, 폴더/텍스트 문서 열기, 재실행 후 북마크와 격자 설정 복원, 목록 복귀, 다른 앱의 전체 화면 위에서 격자 열기·닫기를 확인했습니다. 결과: `.test-artifacts/grid-native-ui-smoke-3.log`.
- Release 앱과 Sparkle의 framework, Installer.xpc, Updater.app, Autoupdate 서명 무결성을 확인했습니다. Developer ID, hardened runtime, arm64/x86_64를 포함합니다. 배포본에는 Debug의 library-validation 예외나 파일 쓰기 권한이 없습니다.
- ZIP·DMG 초안은 `dist/pending-notarization/`에 생성했습니다. DMG 이미지 체크섬 검증이 통과했습니다.
- 당시 공증은 `OneButtonNotary` 키체인 프로필 설정 대기 상태였으며 `appcast.xml`은 빈 피드였습니다. 11월 10일 공증 및 피드 공개를 완료했습니다.
- 공개 GitHub raw feed를 인증 없이 내려받아 저장소 파일과 일치하는지 확인했습니다. Developer ID Release 앱의 **업데이트 → 업데이트 확인…**을 실제로 눌러 Sparkle의 **최신 버전입니다.** 안내를 확인했습니다. 아직 최신 릴리스가 없는 빈 피드 확인이며, 버전 교체 설치 테스트와는 다릅니다. 결과: `.test-artifacts/sparkle-ui-smoke.log`.
- 비공개 테스트 폴더에서 현재 ZIP의 appcast 생성, 버전/URL/크기 검증, 키체인 공개키와 앱 공개키 일치, Sparkle `sign_update --verify`의 EdDSA 검증이 통과했습니다. 최종 공증 후 ZIP을 다시 만들면 반드시 서명과 검증을 다시 수행해야 합니다.
- 잘못된 다운로드 URL과 파일 크기를 넣은 피드를 `PYTHONOPTIMIZE=1`에서도 거부하는 오류 입력 검증이 통과했습니다.
- 저장소: `https://github.com/mindw96/DesktopButton`, 구현 커밋 `7c57eb3`, `main` 푸시 완료. 당시에는 공증된 릴리스와 업데이트 enclosure를 공개하지 않았습니다.

최신 공증·배포 검증 결과는 문서 상단에 기록했습니다. 아래 항목은 0.1.0 초기 구현의 검증 기록입니다.

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
