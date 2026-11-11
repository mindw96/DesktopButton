# 다음 업데이트 준비: 1.1.0 (10)

현재 제출한 **1.0.0 (8)**과 구분해 `codex/sorting-update` 브랜치에서 준비하는 개발 버전입니다. **App Store 업로드·심사 제출·공개는 수행하지 않았습니다.** 현재 제출 기록과 1.0.0용 소개 자료는 `submission-status.json`, `metadata.json`, `review-notes.txt`에 보존합니다.

## 추가 기능

팝업 상단의 위·아래 화살표 **정렬** 메뉴에서 이름·종류·크기·태그·응용 프로그램을 선택합니다. **날짜** 하위 메뉴에는 최근 사용일·추가된 날짜·수정일·생성일이 있습니다. 각 기준은 오름차순·내림차순을 지원하고, 목록·격자에 같은 순서가 적용됩니다.

기준과 방향은 폴더 새로고침·재연결·재실행에도 유지됩니다. 기존 사용자는 이름 오름차순으로 시작하며, 폴더 연결·보기 방식·창 크기·Dock·로그인 설정을 초기화하지 않습니다.

목록·격자에서 **한 번 클릭하면 선택**, **더블클릭하거나 선택 후 Return을 누르면 열기**로 동작합니다. 외부 앱으로 파일을 드래그하는 기능은 유지됩니다. 설정의 **아이콘 크기 → 작게 / 보통 / 크게**는 목록·격자 모두에 적용되고 다음 실행에도 저장됩니다. 기본값 “보통”은 기존 크기와 같습니다. 정렬 메뉴를 사용한 뒤 바깥을 클릭해도 창이 남던 문제를 수정하는 내용도 포함합니다.

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
- 한 번 클릭으로 선택하고, 더블클릭 또는 Return으로 파일 열기
- 목록·격자의 아이콘 크기를 작게·보통·크게 중 선택하고 저장
- 정렬 메뉴 사용 후 바깥을 클릭하면 폴더 창이 닫히도록 개선

## 추가 심사 안내 초안

Version 1.1.0 adds sorting to the existing folder panel. Connect a sample folder and use the up/down-arrow Sort menu in the header. Name, Kind, Size, Tags, and Application are available directly; Last Used, Date Added, Modified, and Created are inside the Date submenu. Select ascending or descending order, switch between list and grid views, refresh, and relaunch to verify that the selected order persists. Application uses the default application that opens each file. Missing metadata sorts last in both directions. Size applies to regular files; directory/package contents are not scanned recursively. Sorting reads metadata only from the user-selected folder and does not change file contents, tags, or dates.

In both list and grid views, a single click now selects an item without opening it. Double-click the item, or press Return after selecting it, to open it. Dragging files into another app remains available. In the gear menu, open “아이콘 크기” (Icon Size) and choose “작게” (Small), “보통” (Medium), or “크게” (Large). Verify that the size changes in both views and is retained after relaunch. Medium keeps the previous default sizes. After changing a sort option, click outside the folder panel to verify that it closes; selecting a menu option or dragging a file should still work normally.

## 제출 전 확인

로컬 실행용 개발 앱: `build/Preview-1.1.0/Folder In Bar.app`.
빌드 10 archive 경로: `build/AppStore/FolderInBar-1.1.0-10.xcarchive`.
빌드 10 배포 패키지 경로: `build/AppStore/export-10/Folder In Bar.pkg`.
위 archive와 서명된 패키지의 생성·검증을 완료했습니다. PKG는 2,104,359바이트이며 SHA-256은 `8b9c419ad255be42b24e6398ab87a28efcb7185176d9d6e0c3823cea1142e1f2`입니다. 단위 테스트 49개와 실제 클릭·크기·정렬·드래그 검증 범위는 [VALIDATION.md](../../VALIDATION.md)에서 확인합니다. 로컬 실행용 개발 앱도 빌드 10으로 교체했습니다.

1. 기존 1.0.0의 실제 심사·출시 상태를 확인합니다.
2. 이 개발 브랜치의 최종 변경을 검토하고, 추가 변경이 있었다면 다시 빌드·검증합니다.
3. 1.1.0 (10)의 로컬 검증 결과와 산출물은 [VALIDATION.md](../../VALIDATION.md)를 확인합니다.
4. 다음 업데이트를 제출할 때 버전·빌드 번호 중복 여부를 확인하고, 스토어 소개·심사 메모·업데이트 설명에 위 내용을 반영합니다. 그때 빌드를 업로드·선택하고 저장값을 다시 확인한 뒤 제출합니다.

이번 개발 작업은 다음 업데이트 제출을 위한 준비이며, 자동 제출을 예약하지 않습니다.
