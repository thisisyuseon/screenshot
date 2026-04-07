import SwiftUI
import SwiftData

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<ScreenshotItem> { !$0.isProcessed },
        sort: \ScreenshotItem.capturedAt,
        order: .reverse
    ) private var pendingItems: [ScreenshotItem]

    @StateObject private var viewModel: ReviewViewModel

    init() {
        // ViewModel은 onAppear에서 modelContext로 초기화
        _viewModel = StateObject(wrappedValue: ReviewViewModel(modelContext: ModelContext(try! ModelContainer(for: ScreenshotItem.self, MonthlyReport.self))))
    }

    var body: some View {
        NavigationStack {
            Group {
                if pendingItems.isEmpty {
                    emptyState
                } else if viewModel.currentIndex >= pendingItems.count {
                    allDoneState
                } else {
                    cardView(for: pendingItems[viewModel.currentIndex])
                }
            }
            .navigationTitle("리뷰")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !pendingItems.isEmpty && viewModel.currentIndex < pendingItems.count {
                        Text("\(viewModel.currentIndex + 1) / \(pendingItems.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("오류", isPresented: $viewModel.showingError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear {
            viewModel.currentIndex = 0
        }
    }

    // MARK: - Card View

    private func cardView(for item: ScreenshotItem) -> some View {
        ReviewCardView(item: item, viewModel: viewModel)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("검토할 스크린샷이 없어요")
                .font(.title2.bold())
            Text("홈 탭에서 스크린샷을 불러와 분석해보세요.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var allDoneState: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("모두 검토 완료!")
                .font(.title2.bold())
            Text("보고서 탭에서 이번 달 정리 결과를 확인하세요.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("처음으로") {
                viewModel.currentIndex = 0
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Review Card

struct ReviewCardView: View {
    let item: ScreenshotItem
    @ObservedObject var viewModel: ReviewViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var selectedCategory: ScreenshotCategory
    @State private var note: String
    @State private var showingFullOCR = false
    @State private var dragOffset: CGSize = .zero

    init(item: ScreenshotItem, viewModel: ReviewViewModel) {
        self.item = item
        self.viewModel = viewModel
        _selectedCategory = State(initialValue: item.category)
        _note = State(initialValue: item.note)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 썸네일
                thumbnailSection

                // AI 분류 결과
                classificationSection

                // 태그
                if !item.tags.isEmpty {
                    tagsSection
                }

                // OCR 텍스트 (접기/펼치기)
                if !item.ocrText.isEmpty {
                    ocrSection
                }

                // 메모 입력
                noteSection

                // 카테고리 변경
                categoryPicker

                // 액션 버튼
                actionButtons
            }
            .padding()
        }
        .gesture(
            DragGesture()
                .onChanged { value in dragOffset = value.translation }
                .onEnded { value in
                    if value.translation.x > 100 {
                        // 오른쪽 스와이프 → 확인
                        confirmAndAdvance()
                    } else if value.translation.x < -100 {
                        // 왼쪽 스와이프 → 건너뜀
                        viewModel.skipItem(item)
                    }
                    dragOffset = .zero
                }
        )
        .offset(x: dragOffset.width * 0.3)
        .animation(.spring(response: 0.3), value: dragOffset)
    }

    private var thumbnailSection: some View {
        Group {
            if let data = item.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 200)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private var classificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI 분석 결과", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedDate(item.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.subheadline)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var tagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(item.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var ocrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showingFullOCR.toggle() }
            } label: {
                HStack {
                    Label("OCR 텍스트", systemImage: "text.viewfinder")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showingFullOCR ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showingFullOCR {
                Text(item.ocrText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("메모")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("메모 추가...", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("카테고리")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ScreenshotCategory.allCases, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        HStack {
                            Image(systemName: cat.icon)
                            Text(cat.rawValue)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedCategory == cat ? colorForCategory(cat).opacity(0.2) : Color.secondary.opacity(0.1))
                        .foregroundStyle(selectedCategory == cat ? colorForCategory(cat) : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            if selectedCategory == cat {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(colorForCategory(cat), lineWidth: 1.5)
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                confirmAndAdvance()
            } label: {
                Label("확인 완료", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.skipItem(item)
                } label: {
                    Label("건너뜀", systemImage: "arrow.right")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.15))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteFromLibraryAndConfirm(
                            item,
                            category: selectedCategory,
                            note: note
                        )
                    }
                } label: {
                    Label("삭제", systemImage: "trash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Text("← 스와이프: 건너뜀  •  → 스와이프: 확인")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func confirmAndAdvance() {
        let vm = ReviewViewModel(modelContext: modelContext)
        viewModel.confirmItem(item, category: selectedCategory, note: note)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
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
