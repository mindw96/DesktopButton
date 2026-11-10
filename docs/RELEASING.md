# Folder In Bar 배포 안내

앱 이름은 **폴더인바(Folder In Bar)**, bundle ID는 `com.onebutton.desktop`, GitHub 저장소는 `mindw96/DesktopButton`입니다. 현재 소스는 **0.4.0 (build 6)**이며, 실제 공증·검증·Release 공개 상태는 [VALIDATION.md](../VALIDATION.md)를 기준으로 확인합니다.

기존 사용자의 설정·업데이트 연결을 유지하기 위해 bundle ID, Sparkle 키·피드, 공증 프로필 `OneButtonNotary`와 내부 Xcode 프로젝트·scheme 이름 `OneButton`은 유지합니다. 앱 번들과 실행 파일은 `Folder In Bar`, 배포 ZIP·DMG 파일은 공백 없는 `FolderInBar-VERSION`을 사용합니다.

이 문서는 `script/release.sh`의 동작과 후속 공개 절차를 설명합니다. 공증 프로필이 준비되지 않았거나 공증에 실패한 산출물은 배포 준비가 끝난 파일로 취급하지 않습니다.

## 1. 배포 환경과 키체인 준비

Xcode command-line tools, Python 3, XcodeGen, GitHub CLI(`gh`), Apple Developer Program의 Developer ID Application 인증서와 그 개인키가 필요합니다. GitHub 저장소와 최종 Release assets는 앱 사용자가 인증 없이 읽을 수 있어야 합니다.

프로젝트 루트에서 실행합니다. `DEVELOPMENT_TEAM`에는 사용할 Apple Developer 팀 ID를 지정합니다. 이 값은 비밀번호가 아닙니다.

```sh
export DEVELOPMENT_TEAM='YOUR_TEAM_ID'
export NOTARYTOOL_PROFILE='OneButtonNotary'
# 동일 이름의 인증서가 여러 개면 Keychain에 표시된 정확한 인증서 이름을 지정합니다.
export SIGN_IDENTITY='Developer ID Application'
security find-identity -v -p codesigning
```

공증 프로필은 **대화형 입력**으로 Keychain에 저장합니다. Apple ID, 팀 ID, 앱 암호 등 인증 정보는 명령이 묻는 입력창에서 제공하세요. 비밀번호나 API 개인키 내용을 문서·명령 이력·저장소에 넣지 않습니다.

```sh
xcrun notarytool store-credentials "$NOTARYTOOL_PROFILE"
xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE"
```

이미 유효한 공증 프로필이 있으면 `NOTARYTOOL_PROFILE`에 그 이름을 지정하면 됩니다. 프로필 이름을 모를 때 임의의 이름이 이미 등록되어 있다고 가정하지 마세요. 스크립트 기본값은 `OneButtonNotary`이며, 시작 시 `notarytool history`로 인증을 확인하고 실패하면 archive 전에 중단합니다. [Apple의 공증 워크플로 안내](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## 2. Sparkle 키 설정

Sparkle은 `project.yml`에서 **2.10.1 exact**로 고정되어 있습니다. 먼저 프로젝트와 패키지를 준비합니다.

```sh
xcodegen generate
xcodebuild -resolvePackageDependencies -project OneButton.xcodeproj \
  -scheme OneButton -derivedDataPath build
SPARKLE_BIN="$PWD/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
```

이 앱의 EdDSA Keychain 계정은 **`com.onebutton.desktop`**입니다. Apple 코드 서명 인증서와 별개의 업데이트 서명 키이며, 개인키는 Keychain에서만 사용합니다.

첫 설정에서만 다음 명령으로 앱 전용 키를 준비합니다. 같은 계정에 키가 이미 있으면 해당 키를 유지하며 공개키를 표시합니다.

```sh
"$SPARKLE_BIN/generate_keys" --account com.onebutton.desktop
```

출력된 **공개키**를 `OneButton/Info.plist`의 `SUPublicEDKey`에 넣습니다. 기존 배포가 있다면 기존 계정과 공개키를 그대로 유지하세요. 공개키 확인만 할 때는 다음 명령을 사용합니다.

```sh
"$SPARKLE_BIN/generate_keys" --account com.onebutton.desktop -p
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' OneButton/Info.plist
```

두 값이 같아야 합니다. 공개키는 저장소에 포함되지만 개인키 export 파일은 만들지 않습니다. 키를 분실했거나 다른 계정으로 바꿔야 하는 경우에는 기존 사용자에게 업데이트를 전달할 수 있는 키 교체 절차를 먼저 확인하세요. 앱의 `SUFeedURL`은 다음 고정 주소입니다.

```text
https://raw.githubusercontent.com/mindw96/DesktopButton/main/appcast.xml
```

Sparkle 기본 구성, 키 관리, 서명 및 앱 배포 원칙은 [공식 Sparkle 문서](https://sparkle-project.org/documentation/)를 참고하세요.

## 3. 버전과 소스 준비

1. `project.yml`의 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`을 올립니다. 예를 들어 `0.3.0 / 5` 다음 배포를 `0.4.0 / 6`로 지정합니다.
2. `MARKETING_VERSION`은 숫자 세 부분(`x.y.z`), build는 증가하는 정수로 유지합니다. Sparkle은 표시 버전보다 **build 번호**로 신버전을 판단합니다.
3. `xcodegen generate`를 실행하고 생성된 프로젝트와 `Package.resolved` 변경을 확인합니다.
4. README의 개발 검증을 실행하고 결과를 `VALIDATION.md`에 기록합니다.

```sh
xcodegen generate
git status --short
git diff --check
```

이미 공개한 tag와 같은 버전의 ZIP/DMG를 덮어쓰지 마세요. 수정이 필요하면 새 version/build로 배포합니다.

## 4. 공증된 ZIP·DMG와 appcast 생성

```sh
DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
NOTARYTOOL_PROFILE="$NOTARYTOOL_PROFILE" \
SIGN_IDENTITY="$SIGN_IDENTITY" \
./script/release.sh
```

스크립트는 다음 순서로 실행됩니다.

1. Keychain 공증 프로필의 인증을 확인합니다.
2. Release를 `arm64 + x86_64` Universal 앱으로 archive하고 Developer ID 방식으로 export합니다. 이 과정에서 Sparkle 내부 helper와 XPC 서비스, `Contents/Helpers/FolderNameMigrationHelper.app`도 같은 팀으로 배포 서명합니다.
3. 앱 코드 서명, 아키텍처, 샌드박스와 네트워크 권한을 검증합니다. 이름 변경 helper의 Universal 아키텍처·같은 서명 팀·추가 entitlement 없음도 확인합니다. Debug의 library validation 예외, `get-task-allow`, 사용자 선택 파일 쓰기 권한이 Release에 있으면 중단합니다.
4. 앱을 공증에 제출하고 결과를 기다린 뒤 앱에 ticket을 staple하고 Gatekeeper 검증을 수행합니다.
5. staple된 앱으로 최종 ZIP과 `/Applications` 바로가기를 포함한 DMG를 만듭니다. DMG 자체도 Developer ID 서명·공증·staple·이미지 검증을 거칩니다.
6. 최종 ZIP을 Sparkle의 전용 Keychain 계정으로 서명해 appcast를 생성하고 앱 metadata와 대조합니다. 현재 스크립트는 이번 ZIP 한 개로 피드를 생성하며 이전 버전 목록과 delta를 자동 보관하지 않습니다.
7. 루트의 `appcast.xml`을 갱신하고 ZIP·DMG의 SHA-256 목록을 만듭니다.

| 경로 | 용도 |
| --- | --- |
| `build/OneButton.xcarchive` | Universal Release archive |
| `build/export/Folder In Bar.app` | 공증·staple된 배포 앱 |
| `build/notarization.zip` | 앱 공증 제출용 중간 파일 |
| `dist/FolderInBar-VERSION.zip` | Sparkle 업데이트 및 직접 다운로드용 최종 ZIP |
| `dist/FolderInBar-VERSION.dmg` | 직접 설치용 최종 DMG |
| `dist/SHA256SUMS` | 이번 ZIP·DMG의 SHA-256 |
| `dist/appcast.xml`, `appcast.xml` | 이번 업데이트 피드 |

`build/`와 `dist/`는 Git에서 제외합니다. 스크립트가 중간에 실패하면 해당 실행의 배포를 중단하고 원인을 해결한 뒤 다시 실행하세요. 남아 있는 과거 `dist/` 파일이나 미공증 중간 파일을 성공한 결과로 오인하지 않도록 마지막 성공 로그와 버전·검증 결과를 함께 확인합니다. `build/notarization.zip` 및 임시 미공증 ZIP/DMG를 Release asset이나 appcast에 넣지 않습니다.

## 5. 공개 전 검증

이번 export에서 버전을 읽고 최종 파일을 확인합니다.

```sh
APP="$PWD/build/export/Folder In Bar.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SPARKLE_BIN="$PWD/build/SourcePackages/artifacts/sparkle/Sparkle/bin"

codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/Folder In Bar" # arm64와 x86_64가 모두 포함되어야 합니다.
xcrun stapler validate "dist/FolderInBar-$VERSION.dmg"
hdiutil verify "dist/FolderInBar-$VERSION.dmg"
(cd dist && shasum -a 256 -c SHA256SUMS)
python3 script/verify_appcast.py dist/appcast.xml "dist/FolderInBar-$VERSION.zip" "$APP"
```

`verify_appcast.py`는 version/build, 최소 macOS, 다운로드 URL, 파일 크기와 서명 형식을 대조합니다. 별도로 최종 ZIP의 EdDSA 서명을 실제 검증하고, 서명 계정의 공개키가 export된 앱에 들어 있는지 확인합니다.

```sh
SIGNATURE="$(python3 - <<'PY'
import xml.etree.ElementTree as ET
item = ET.parse('dist/appcast.xml').find('channel/item/enclosure')
print(item.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'])
PY
)"
"$SPARKLE_BIN/sign_update" --account com.onebutton.desktop \
  --verify "dist/FolderInBar-$VERSION.zip" "$SIGNATURE"
"$SPARKLE_BIN/generate_keys" --account com.onebutton.desktop -p
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist"
```

최종 ZIP을 새 폴더에 풀어 앱의 서명과 staple을 다시 확인하고, DMG를 열어 앱과 Applications 바로가기를 확인합니다. 앱은 `/Applications` 등 쓰기 가능한 설치 위치로 복사해 실행하세요. 메뉴 재열기, 폴더 접근 복원, 목록·격자 전환, 파일 열기, 업데이트 확인을 점검합니다.

첫 공개 이후에는 별도의 테스트 피드와 서로 다른 build 번호의 공증 앱으로 **구버전 → 다운로드 → 설치 → 재실행** 흐름도 확인합니다. 피드 검증 또는 “최신 버전” 창만으로 실제 교체 설치가 검증되었다고 기록하지 않습니다. 배포 파일에 수정이 생기면 공증·패키징·Sparkle 서명·SHA-256 생성을 다시 수행해야 합니다.

## 6. 소스 commit·tag와 GitHub Release

빌드한 소스와 공개할 파일이 일치하는지 확인합니다. feed가 아직 없는 asset을 가리키는 시간을 피하기 위해 **Release 파일을 먼저 공개하고 appcast를 마지막에 push**합니다.

먼저 이번 릴리스의 실제 변경 내용을 `build/release-notes.md`에 작성합니다. 아래 예시는 이미 `origin`이 `https://github.com/mindw96/DesktopButton.git`이고 공개 브랜치가 `main`인 경우입니다.

```sh
git remote -v
git status --short
# appcast는 파일 공개 후 별도 commit으로 반영합니다.
git add -- . ':!appcast.xml'
git diff --cached --name-only
```

staged 목록에 `appcast.xml`이나 비밀 파일·빌드 산출물이 없는지 확인한 뒤 commit과 tag를 만듭니다. 기존에 stage한 appcast가 있으면 먼저 staging에서 제외합니다.

```sh
git commit -m "Release Folder In Bar $VERSION"
git tag -a "v$VERSION" -m "Folder In Bar $VERSION"
git push origin main
git push origin "v$VERSION"

gh release create "v$VERSION" \
  "dist/FolderInBar-$VERSION.zip" \
  "dist/FolderInBar-$VERSION.dmg" \
  dist/SHA256SUMS \
  --repo mindw96/DesktopButton --verify-tag --draft \
  --title "Folder In Bar $VERSION" --notes-file build/release-notes.md

gh release view "v$VERSION" --repo mindw96/DesktopButton \
  --json tagName,isDraft,assets
```

첨부 파일 이름과 크기, tag, 릴리스 노트를 확인한 뒤 공개합니다. `dist/*` wildcard 대신 이번 버전 파일을 명시해 이전 빌드가 섞이지 않게 합니다.

```sh
gh release edit "v$VERSION" --repo mindw96/DesktopButton --draft=false
```

## 7. 공개 다운로드와 raw feed 확인

인증 없이 Release 파일을 다시 받아 로컬 최종 파일과 비교합니다. GitHub Release 파일은 공개 후에도 전파에 시간이 걸릴 수 있으므로 실패 상태에서는 appcast push를 진행하지 않습니다.

```sh
VERIFY_DIR="$(mktemp -d "$PWD/build/published-check.XXXXXX")"
RELEASE_URL="https://github.com/mindw96/DesktopButton/releases/download/v$VERSION"
curl --fail --location "$RELEASE_URL/FolderInBar-$VERSION.zip" \
  --output "$VERIFY_DIR/FolderInBar-$VERSION.zip"
curl --fail --location "$RELEASE_URL/FolderInBar-$VERSION.dmg" \
  --output "$VERIFY_DIR/FolderInBar-$VERSION.dmg"
curl --fail --location "$RELEASE_URL/SHA256SUMS" \
  --output "$VERIFY_DIR/SHA256SUMS"
(cd "$VERIFY_DIR" && shasum -a 256 -c SHA256SUMS)
cmp "dist/FolderInBar-$VERSION.zip" "$VERIFY_DIR/FolderInBar-$VERSION.zip"
cmp "dist/FolderInBar-$VERSION.dmg" "$VERIFY_DIR/FolderInBar-$VERSION.dmg"
```

확인 후 appcast를 공개 브랜치에 반영합니다.

```sh
git add appcast.xml
git commit -m "Publish Folder In Bar $VERSION update feed"
git push origin main

curl --fail --location \
  'https://raw.githubusercontent.com/mindw96/DesktopButton/main/appcast.xml' \
  --output "$VERIFY_DIR/appcast.xml"
cmp appcast.xml "$VERIFY_DIR/appcast.xml"
python3 script/verify_appcast.py "$VERIFY_DIR/appcast.xml" \
  "$VERIFY_DIR/FolderInBar-$VERSION.zip" "$APP"
```

raw feed에 이전 내용이 보이면 전파 후 다시 확인합니다. 공개 피드의 enclosure가 이번 Release URL을 가리키며 실제 받은 파일의 크기·버전과 일치하는지 확인하고, 실행 중인 앱의 **앱 업데이트 확인…**으로 마지막 점검을 수행합니다. 결과와 남은 검증 항목을 `VALIDATION.md`에 기록하고 commit·push합니다.

## 기존 앱 이름 변경 검증

0.4.0부터 새 앱의 첫 실행에서 기존 `OneButton.app` 경로를 감지합니다. Sparkle는 기존 경로에 설치하므로, 메인 앱이 번들 안의 이름 변경 helper를 `NSWorkspace`로 실행하고, 실행 성공을 확인한 뒤 스스로 종료합니다. Helper는 자신의 상위 번들·서명 팀과 정확히 일치하는 실행 중 앱이 있다면 종료를 기다리고, 같은 폴더 안에서 `RENAME_EXCL`로 이름을 변경합니다. 대상 충돌·권한 오류에서는 덮어쓰거나 관리자 권한을 요청하지 않습니다.

구버전 0.2.2 및 0.3.0부터 실제 업데이트를 확인할 때 기존 경로의 부재, 새 경로의 프로세스, 보안 범위 북마크 복원과 실제 폴더 읽기, 로그인 등록의 상태와 새 경로를 함께 확인하세요. 로그인 등록은 이동 전에 해제하지 않습니다. 새 프로세스는 5분 이내의 일회성 기록에 한해서 기존 enabled 등록이 사라졌을 때만 복구하며, 기존 off 또는 승인 대기를 자동으로 켜지 않습니다. 실제 로그아웃·로그인을 수행하지 않은 경우 다음 로그인 시 실행까지 검증했다고 기록하지 않습니다.

샌드박스 앱이 호출한 `NSWorkspace.OpenConfiguration.arguments`는 macOS가 무시합니다. 따라서 메인 앱에서 경로나 PID 인자를 넘기지 않고 helper가 자신의 상위 앱 경로에 일치하는 실행 프로세스를 직접 찾습니다. [Apple API 문서](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/arguments)

Helper는 다른 앱에 종료 Apple Event를 보내지 않습니다. 이름 변경 전 검사 또는 rename이 실패하면 검증된 원본 앱을 재실행하며, 원본 파일 교체가 감지된 경우에는 자동 실행하지 않습니다.
