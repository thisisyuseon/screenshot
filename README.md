# SnapSort

아이폰 카메라 앨범의 스크린샷을 AI로 자동 분류·정리하는 iOS 앱.

## 핵심 기능

| 기능 | 설명 |
|---|---|
| 스크린샷 수집 | 이번 달 / 지난 달 스크린샷 자동 가져오기 |
| AI 분석 | Vision OCR + Claude API로 내용 추출 및 분류 |
| 수동 리뷰 | 카드 스와이프 UI로 AI 결과 검토·수정 |
| 월간 보고서 | PDF 생성 및 앱 내 뷰어 |
| 앨범 정리 | 처리 완료된 스크린샷 일괄 삭제 |

## 카테고리

- **나중에 확인** — 링크, 가격, 할 일
- **영감** — 디자인, 글귀, 아이디어
- **정보/지식** — 뉴스, 레시피, 튜토리얼
- **기타** — 분류 불명확

## 기술 스택

- **UI**: SwiftUI
- **사진 접근**: PhotosUI / PHPhotoLibrary
- **OCR**: Vision framework
- **AI 분류**: Claude API (claude-haiku-4-5)
- **PDF**: PDFKit
- **로컬 저장**: SwiftData (iOS 17+)

## 프로젝트 구조

```
screenshot/
├── App/
│   ├── SnapSortApp.swift       # 앱 진입점, ModelContainer 설정
│   └── ContentView.swift       # 탭 네비게이션
├── Features/
│   ├── Home/HomeView.swift     # 현황 카드, 처리 시작
│   ├── Review/
│   │   ├── ReviewView.swift    # 카드 스와이프 리뷰 UI
│   │   └── ReviewViewModel.swift
│   ├── Report/
│   │   ├── ReportListView.swift
│   │   ├── ReportDetailView.swift
│   │   └── PDFGenerator.swift
│   └── Settings/SettingsView.swift
├── Services/
│   ├── PhotosService.swift     # 사진 접근/삭제
│   ├── OCRService.swift        # Vision OCR
│   └── ClaudeService.swift     # Claude API
├── Models/
│   └── Screenshot.swift        # SwiftData 모델
└── Resources/
    └── Info.plist
```

## 시작하기

1. Xcode 15+ 에서 프로젝트 열기
2. `설정 > Claude API 키` 입력 (console.anthropic.com에서 발급)
3. iPhone 실기기에서 빌드 (시뮬레이터는 Photos 일부 제한)
4. 홈 탭에서 "스크린샷 정리 시작" 버튼 탭

## 요구사항

- iOS 17.0+
- Xcode 15.0+
- Claude API 키 (Anthropic Console)