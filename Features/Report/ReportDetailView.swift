import SwiftUI
import PDFKit

struct ReportDetailView: View {
    let report: MonthlyReport

    @State private var selectedCategory: ScreenshotCategory? = nil
    @State private var showingPDF = false
    @State private var showingDeleteConfirm = false
    @Environment(\.modelContext) private var modelContext

    var displayItems: [ScreenshotItem] {
        if let cat = selectedCategory {
            return report.screenshots.filter { $0.category == cat }
        }
        return report.screenshots
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 요약 통계
                summarySection

                // 카테고리 필터
                categoryFilter

                // 스크린샷 그리드
                screenshotGrid

                // 삭제 버튼
                if report.screenshots.contains(where: { !$0.isDeletedFromLibrary }) {
                    deleteButton
                }
            }
            .padding()
        }
        .navigationTitle(report.displayMonth)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if report.pdfData != nil {
                    Button {
                        showingPDF = true
                    } label: {
                        Label("PDF", systemImage: "doc.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showingPDF) {
            if let pdfData = report.pdfData {
                PDFViewerSheet(pdfData: pdfData, title: "\(report.displayMonth) 보고서")
            }
        }
        .confirmationDialog(
            "앨범에서 삭제",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                Task { await deleteAllFromLibrary() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 보고서에 포함된 스크린샷을 아이폰 사진 앱에서 삭제합니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        HStack(spacing: 16) {
            ForEach(ScreenshotCategory.allCases, id: \.self) { cat in
                let count = report.screenshots.filter { $0.category == cat }.count
                VStack {
                    Image(systemName: cat.icon)
                        .foregroundStyle(colorForCategory(cat))
                    Text("\(count)")
                        .font(.headline)
                    Text(cat.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button {
                    selectedCategory = nil
                } label: {
                    Text("전체")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedCategory == nil ? Color.blue : Color.secondary.opacity(0.15))
                        .foregroundStyle(selectedCategory == nil ? .white : .primary)
                        .clipShape(Capsule())
                }

                ForEach(ScreenshotCategory.allCases, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        Text(cat.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == cat ? colorForCategory(cat) : Color.secondary.opacity(0.15))
                            .foregroundStyle(selectedCategory == cat ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var screenshotGrid: some View {
        LazyVStack(spacing: 12) {
            ForEach(displayItems) { item in
                ScreenshotReportCard(item: item)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Label("앨범에서 스크린샷 삭제", systemImage: "trash")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Actions

    private func deleteAllFromLibrary() async {
        let ids = report.screenshots
            .filter { !$0.isDeletedFromLibrary }
            .map { $0.localIdentifier }

        do {
            try await PhotosService.shared.deleteAssets(identifiers: ids)
            for item in report.screenshots {
                item.isDeletedFromLibrary = true
            }
            try? modelContext.save()
        } catch {
            // 에러 처리는 상위 뷰에서 처리
        }
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

// MARK: - Screenshot Card in Report

struct ScreenshotReportCard: View {
    let item: ScreenshotItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 썸네일
            if let data = item.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate(item.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                if !item.tags.isEmpty {
                    Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }

                if !item.note.isEmpty {
                    Text("메모: \(item.note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.isDeletedFromLibrary {
                Image(systemName: "trash.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.5))
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - PDF Viewer Sheet

struct PDFViewerSheet: View {
    let pdfData: Data
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(data: pdfData)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("닫기") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: pdfData, preview: SharePreview(title, image: Image(systemName: "doc.fill")))
                    }
                }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(data: data)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {}
}
