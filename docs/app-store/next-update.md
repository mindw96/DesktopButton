# 다음 업데이트 준비: 1.1.0 (9)

현재 제출한 **1.0.0 (8)**과 구분해 `codex/sorting-update` 브랜치에서 준비하는 개발 버전입니다. **App Store 업로드·심사 제출·공개는 수행하지 않았습니다.** 현재 제출 기록과 1.0.0용 소개 자료는 `submission-status.json`, `metadata.json`, `review-notes.txt`에 보존합니다.

## 추가 기능

팝업 상단의 위·아래 화살표 **정렬** 메뉴에서 이름·종류·크기·태그·응용 프로그램을 선택합니다. **날짜** 하위 메뉴에는 최근 사용일·추가된 날짜·수정일·생성일이 있습니다. 각 기준은 오름차순·내림차순을 지원하고, 목록·격자에 같은 순서가 적용됩니다.

기준과 방향은 폴더 새로고침·재연결·재실행에도 유지됩니다. 기존 사용자는 이름 오름차순으로 시작하며, 폴더 연결·보기 방식·창 크기·Dock·로그인 설정을 초기화하지 않습니다. 항목의 선택, 일반 클릭과 외부 앱 드래그는 유지됩니다.

- 이름·종류·기본 앱·태그 이름은 macOS 자연 정렬을 사용합니다.
- 응용 프로그램은 파일을 여는 기본 앱의 시스템 표시 이름입니다.
- 최근 사용일은 macOS 파일 메타데이터입니다. 파일을 읽은 시각으로 대체하거나 앱이 새 날짜를 기록하지 않습니다.
- 추가된 날짜 등은 파일시스템·Spotlight 상태에 따라 없을 수 있습니다. 값이 없는 항목은 정렬 방향과 관계없이 뒤에 표시합니다.
- 크기는 일반 파일의 바이트 수입니다. 폴더·패키지 내부의 전체 크기를 재귀 계산하지 않습니다.
- 태그는 태그 이름 목록을 비교하며 Finder의 색상별 그룹 배치를 복제하지 않습니다.
- 같은 값은 이름 자연 오름차순, 이어서 파일 경로 순으로 정렬합니다.

Store 개인정보 manifest에는 사용자 선택 파일의 날짜·메타데이터 접근 사유 `FileTimestamp / 3B52.1`을 추가했습니다. 폴더의 읽기 권한을 확대하거나 파일 날짜·태그·내용을 변경하지 않습니다. [Apple의 필수 사유 API 안내](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

## App Store 업데이트 설명 초안

목록과 아이콘 보기에서 파일을 원하는 순서로 정렬할 수 있습니다.

- 이름, 종류, 크기, 태그, 파일을 여는 기본 앱으로 정렬
- 최근 사용일, 추가된 날짜, 수정일, 생성일로 날짜 정렬
- 오름차순·내림차순 선택 및 다음 실행에도 정렬 설정 유지

## 추가 심사 안내 초안

Version 1.1.0 adds sorting to the existing folder panel. Connect a sample folder and use the up/down-arrow Sort menu in the header. Name, Kind, Size, Tags, and Application are available directly; Last Used, Date Added, Modified, and Created are inside the Date submenu. Select ascending or descending order, switch between list and grid views, refresh, and relaunch to verify that the selected order persists. Application uses the default application that opens each file. Missing metadata sorts last in both directions. Size applies to regular files; directory/package contents are not scanned recursively. Sorting reads metadata only from the user-selected folder and does not change file contents, tags, or dates. Existing opening and drag-and-drop actions remain available.

## 제출 전 확인

로컬 실행용 개발 앱: `build/Preview-1.1.0/Folder In Bar.app`.
준비한 archive: `build/AppStore/FolderInBar-1.1.0-9.xcarchive`.
서명·권한 검증을 마친 배포 패키지: `build/AppStore/export-9/Folder In Bar.pkg`.
패키지 SHA-256: `506bf93eb08908c432168acbe965fe52c2e47d813fe465871817695d753fc08d`.

1. 기존 1.0.0의 실제 심사·출시 상태를 확인합니다.
2. 이 개발 브랜치의 최종 변경을 검토하고, 추가 변경이 있었다면 다시 빌드·검증합니다.
3. 준비한 1.1.0 (9)의 로컬 검증 결과와 산출물은 [VALIDATION.md](../../VALIDATION.md)를 확인합니다.
4. 다음 업데이트를 제출할 때 버전·빌드 번호 중복 여부를 확인하고, 스토어 소개·심사 메모·업데이트 설명에 위 내용을 반영합니다. 그때 빌드를 업로드·선택하고 저장값을 다시 확인한 뒤 제출합니다.

이번 개발 작업은 다음 업데이트 제출을 위한 준비이며, 자동 제출을 예약하지 않습니다.
