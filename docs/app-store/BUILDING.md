# Mac App Store 빌드와 제출

Mac App Store판은 별도 **`FolderInBarAppStore` scheme**으로 빌드합니다. 현재 준비 버전은 **1.0.0 (build 7)**이며, App Store Connect 앱 ID는 **6833273093**입니다. 앱 등록·빌드 생성은 심사 제출이나 공개 완료를 뜻하지 않습니다. 실제 진행 결과는 저장소 루트의 [VALIDATION.md](../../VALIDATION.md)를 확인하세요.

| 구분 | Mac App Store | GitHub 직접 배포 |
| --- | --- | --- |
| Scheme | `FolderInBarAppStore` | `OneButton` |
| 현재 버전 | 1.0.0 (7), 제출 준비 | 0.4.0 (6), 공개됨 |
| 업데이트 | App Store | Sparkle |
| 서명·패키지 | Store 배포 서명·프로필, 서명된 PKG | Developer ID, 공증·staple, ZIP·DMG |
| 이름 변경 helper | 포함하지 않음 | 기존 `OneButton.app` 이름 변경용 포함 |
| Sandbox 권한 | 선택한 파일 읽기, 앱 범위 북마크 | 같은 권한과 Sparkle 통신 권한 |

Store판에는 Sparkle 코드·프레임워크·업데이트 메뉴·관련 설정과 예외 권한을 넣지 않습니다. `script/release.sh`는 직접 배포 전용이며, Store 제출에는 별도 공증이나 Sparkle 피드 갱신을 하지 않습니다.

## 필요한 계정과 서명

- Xcode **Settings → Accounts**에 팀 `4J7HGK26PF`를 사용할 수 있는 Apple Developer 계정이 로그인되어 있어야 합니다. 브라우저의 App Store Connect 로그인과 Xcode 로그인은 별개입니다.
- Apple Developer 계정의 계약 상태와 `com.onebutton.desktop` App ID를 확인합니다. 자동 서명은 `-allowProvisioningUpdates`로 필요한 프로필을 관리합니다.
- Archive에는 개발 서명을 사용할 수 있지만, 배포 export에는 **Apple Distribution**(또는 **3rd Party Mac Developer Application**) 앱 인증서와 해당 개인 키, Mac App Store 배포 프로필이 필요합니다.
- PKG에는 **Mac Installer Distribution**(키체인에는 **3rd Party Mac Developer Installer**로 표시될 수 있음) 인증서와 해당 개인 키가 필요합니다. Developer ID 인증서와 공증용 `OneButtonNotary` 프로필은 Store 배포 자격 증명이 아닙니다.

## Archive와 export

저장소 루트에서 실행합니다. 프로젝트 설정을 바꿨다면 먼저 `xcodegen generate`를 실행합니다. 아래 명령은 Apple Silicon과 Intel을 함께 포함합니다.

```sh
xcodebuild -project OneButton.xcodeproj -scheme FolderInBarAppStore \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/AppStore/DerivedData \
  -archivePath build/AppStore/FolderInBar-1.0.0-7.xcarchive \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  -allowProvisioningUpdates archive

xcodebuild -exportArchive \
  -archivePath build/AppStore/FolderInBar-1.0.0-7.xcarchive \
  -exportPath build/AppStore/export \
  -exportOptionsPlist AppStore/ExportOptions.plist \
  -allowProvisioningUpdates
```

`AppStore/ExportOptions.plist`는 `method=app-store-connect`, `destination=export`, 자동 서명을 사용합니다. 버전과 build 번호를 자동 변경하지 않습니다. 제출 버전이 바뀌면 `project.yml`의 Store target 버전과 경로를 함께 갱신하세요.

Store 개발 빌드의 출력은 DerivedData의 `Build/Products/AppStore/Debug/Folder In Bar.app`입니다. 같은 빌드 폴더에서 scheme을 바꾸어도 직접 배포판의 Sparkle 파일이 섞이지 않도록 출력 경로를 분리합니다. Archive 안의 앱 경로는 `Products/Applications/Folder In Bar.app`입니다.

## 배포 산출물 확인

**Export한 앱**에 다음 검증을 실행합니다. Archive의 개발 서명 앱은 Store 배포 서명 검증을 통과하지 않을 수 있습니다.

```sh
python3 script/verify_app_store.py \
  'build/AppStore/export/Folder In Bar.app' --release
```

Xcode가 앱 대신 PKG를 내보냈다면, 실제 생성된 PKG 파일명으로 아래 명령을 실행합니다. `pkg-expanded`는 아직 없는 경로여야 합니다. 이는 압축만 풀며 앱을 설치하지 않습니다.

```sh
pkgutil --check-signature 'build/AppStore/export/Folder In Bar.pkg'
pkgutil --expand-full 'build/AppStore/export/Folder In Bar.pkg' \
  build/AppStore/pkg-expanded
find build/AppStore/pkg-expanded -type d -name 'Folder In Bar.app'
```

마지막 명령이 출력한 앱 경로를 `verify_app_store.py`의 인자로 전달하고 `--release`를 붙입니다. 검증은 Universal 구성, 앱 서명·팀, 정확한 앱 ID의 배포 프로필, sandbox와 읽기 권한, 디버깅 권한 제거, 개인정보 manifest, Sparkle·이름 변경 helper 제외를 확인합니다. PKG 서명도 별도로 확인해야 합니다.

## 업로드와 심사 제출

검증이 끝난 같은 Archive를 업로드합니다. 이 명령은 App Store Connect로 실제 전송합니다.

```sh
xcodebuild -exportArchive \
  -archivePath build/AppStore/FolderInBar-1.0.0-7.xcarchive \
  -exportPath build/AppStore/upload \
  -exportOptionsPlist AppStore/ExportOptions-Upload.plist \
  -allowProvisioningUpdates
```

`ExportOptions-Upload.plist`는 `destination=upload`입니다. 업로드 성공 후 App Store Connect의 처리 완료를 확인하고, 해당 build를 버전에 선택한 뒤 스크린샷·설명·지원 및 개인정보 URL·개인정보 답변·연령 등급·심사 정보를 완료하여 제출합니다. 이 앱은 무료, 심사 승인 후 자동 공개로 준비합니다. 제출 상태, 심사 승인, 스토어 공개는 각각 확인해야 합니다.

## 기존 설치와 설정

두 배포판은 bundle ID **`com.onebutton.desktop`**와 설정 키를 공유하므로 별도 앱처럼 함께 설치·실행하는 구성을 지원하지 않습니다. Store판의 코드에는 기존 폴더 북마크, 보기 모드, 창 크기, Dock 설정을 지우거나 바꾸는 이관 동작이 없습니다. 로그인 실행은 macOS의 실제 등록 상태를 읽습니다.

이 설계만으로 직접 배포판에서 Store 설치판으로 교체했을 때 설정이 유지된다고 보장할 수는 없습니다. 실제 App Store 설치로 교체한 뒤 폴더 접근, 저장한 설정, 로그인 시 자동 실행을 검증해야 합니다. Store 설치 확인 전에는 기존 앱과 설정을 보존하고, 사용자의 실제 폴더 연결을 테스트용 값으로 덮어쓰지 마세요.
