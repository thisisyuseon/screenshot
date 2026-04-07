import SwiftUI
import SwiftData
import Photos

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScreenshotItem.capturedAt, order: .reverse) private var allScreenshots: [ScreenshotItem]

    @StateObject private var photosService = PhotosService.shared
    @StateObject private var claudeService = ClaudeService.shared

    @State private var isProcessing = false
    @State private var processingMessage = ""
    @State private var processingProgress: Double = 0
    @State private var showingPeriodPicker = false
    @State private var selectedPeriod: FetchPeriod = .thisMonth
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var errorMessage: String?
    @State private var showingError = false

    enum FetchPeriod: String, CaseIterable {
        case thisMonth = "이번 달"
        case lastMonth = "지난 달"
    }

    private var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private var thisMonthScreenshots: [ScreenshotItem] {
        allScreenshots.filter { $0.reportMonth == currentMonthKey }
    }

    private var pendingCount: Int {
        thisMonthScreenshots.filter { !$0.isProcessed }.count
    }

    private var processedCount: Int {
        thisMonthScreenshots.filter { $0.isProcessed }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 상태 카드
                    statusCard

                    // 처리 시작 버튼
                    if authorizationStatus == .authorized || authorizationStatus == .limited {
                        actionButton
                    } else {
                        permissionButton
                    }

                    // 카테고리별 현황
                    if processedCount > 0 {
                        categoryBreakdown
                    }
                }
                .padding()
            }
            .navigationTitle("SnapSort")
            .navigationBarTitleDisplayMode(.large)
            .task {
                authorizationStatus = await photosService.requestAuthorization()
            }
            .alert("오류", isPresented: $showingError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
            .overlay {
                if isProcessing {
                    processingOverlay
                }
            }
        }
    }

    // MARK: - Subviews

    private var statusCard: some View {
        VStack(spacing: 12) {
            Text(monthDisplayName(currentMonthKey))
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                VStack {
                    Text("\(thisMonthScreenshots.count)")
                        .font(.system(size: 40, weight: .bold))
                    Text("전체")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 50)

                VStack {
                    Text("\(processedCount)")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.green)
                    Text("정리됨")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 50)

                VStack {
                    Text("\(pendingCount)")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("미처리")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionButton: some View {
        VStack(spacing: 12) {
            Picker("기간", selection: $selectedPeriod) {
                ForEach(FetchPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await startProcessing() }
            } label: {
                Label("스크린샷 정리 시작", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(claudeService.apiKey.isEmpty)

            if claudeService.apiKey.isEmpty {
                Text("Claude API 키를 설정 탭에서 입력하세요.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var permissionButton: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("사진 라이브러리 접근 권한이 필요합니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("설정에서 허용하기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("카테고리 현황")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ScreenshotCategory.allCases, id: \.self) { category in
                    let count = thisMonthScreenshots.filter { $0.category == category && $0.isProcessed }.count
                    CategoryStatCard(category: category, count: count)
                }
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: processingProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 240)

                Text(processingMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Processing Logic

    private func startProcessing() async {
        isProcessing = true
        processingProgress = 0
        processingMessage = "스크린샷 불러오는 중..."

        do {
            // 1. 스크린샷 가져오기
            let assets: [ScreenshotAsset]
            switch selectedPeriod {
            case .thisMonth:
                assets = try await photosService.fetchThisMonthScreenshots()
            case .lastMonth:
                assets = try await photosService.fetchLastMonthScreenshots()
            }

            if assets.isEmpty {
                processingMessage = "스크린샷이 없습니다."
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                isProcessing = false
                return
            }

            processingMessage = "\(assets.count)개 스크린샷 분석 중..."

            // 2. 각 스크린샷 OCR + 분류
            for (index, asset) in assets.enumerated() {
                // 이미 처리된 항목 건너뜀
                if allScreenshots.contains(where: { $0.localIdentifier == asset.localIdentifier && $0.isProcessed }) {
                    processingProgress = Double(index + 1) / Double(assets.count)
                    continue
                }

                processingMessage = "(\(index + 1)/\(assets.count)) 분석 중..."

                // 썸네일 로드
                let thumbnail = await photosService.loadThumbnail(for: asset.asset)

                // OCR
                let ocrText: String
                if let thumb = thumbnail {
                    ocrText = (try? await OCRService.shared.recognizeText(from: thumb)) ?? ""
                } else {
                    ocrText = ""
                }

                // Claude 분류
                let result: ClassificationResult
                do {
                    result = try await claudeService.classify(ocrText: ocrText, thumbnail: thumbnail)
                } catch {
                    result = ClassificationResult(category: .other, summary: "분류 실패", tags: [])
                }

                // SwiftData에 저장
                let monthKey = photosService.monthKey(for: asset.capturedAt)
                let item = ScreenshotItem(
                    localIdentifier: asset.localIdentifier,
                    capturedAt: asset.capturedAt,
                    reportMonth: monthKey
                )
                item.ocrText = ocrText
                item.category = result.category
                item.summary = result.summary
                item.tags = result.tags
                item.isProcessed = false  // 리뷰 탭에서 사용자가 확인 후 true로 변경
                item.thumbnailData = thumbnail?.jpegData(compressionQuality: 0.5)
                modelContext.insert(item)

                processingProgress = Double(index + 1) / Double(assets.count)
            }

            try? modelContext.save()
            processingMessage = "완료! 리뷰 탭에서 확인하세요."
            try? await Task.sleep(nanoseconds: 1_500_000_000)

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }

        isProcessing = false
    }

    private func monthDisplayName(_ key: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: key) {
            formatter.dateFormat = "yyyy년 M월"
            return formatter.string(from: date)
        }
        return key
    }
}

// MARK: - Supporting Views

struct CategoryStatCard: View {
    let category: ScreenshotCategory
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundStyle(colorForCategory(category))
            VStack(alignment: .leading) {
                Text(category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(count)개")
                    .font(.headline)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func colorForCategory(_ category: ScreenshotCategory) -> Color {
        switch category {
        case .reviewLater: return .blue
        case .inspiration: return .yellow
        case .info: return .green
        case .other: return .gray
        }
    }
}
