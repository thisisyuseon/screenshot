import SwiftUI
import SwiftData

struct ReportListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MonthlyReport.createdAt, order: .reverse) private var reports: [MonthlyReport]
    @Query(filter: #Predicate<ScreenshotItem> { $0.isProcessed }) private var processedItems: [ScreenshotItem]

    @State private var showingGenerateConfirm = false
    @State private var isGenerating = false

    private var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private var hasCurrentMonthReport: Bool {
        reports.contains { $0.month == currentMonthKey }
    }

    private var currentMonthProcessed: [ScreenshotItem] {
        processedItems.filter { $0.reportMonth == currentMonthKey }
    }

    var body: some View {
        NavigationStack {
            Group {
                if reports.isEmpty {
                    emptyState
                } else {
                    reportList
                }
            }
            .navigationTitle("보고서")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !currentMonthProcessed.isEmpty {
                        Button {
                            showingGenerateConfirm = true
                        } label: {
                            Label("보고서 생성", systemImage: "doc.badge.plus")
                        }
                    }
                }
            }
            .confirmationDialog(
                "이번 달 보고서를 생성할까요?",
                isPresented: $showingGenerateConfirm,
                titleVisibility: .visible
            ) {
                Button("생성하기") {
                    Task { await generateCurrentMonthReport() }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("\(currentMonthProcessed.count)개 스크린샷으로 보고서를 만듭니다.")
            }
            .overlay {
                if isGenerating {
                    ProgressView("보고서 생성 중...")
                        .padding(24)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var reportList: some View {
        List {
            ForEach(reports) { report in
                NavigationLink(destination: ReportDetailView(report: report)) {
                    ReportRowView(report: report)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    modelContext.delete(reports[index])
                }
                try? modelContext.save()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("아직 보고서가 없어요")
                .font(.title2.bold())
            Text("스크린샷을 정리하고 나면 보고서를 생성할 수 있어요.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func generateCurrentMonthReport() async {
        isGenerating = true

        let report = MonthlyReport(month: currentMonthKey)
        report.screenshots = currentMonthProcessed
        report.totalCount = currentMonthProcessed.count

        // PDF 생성
        if let pdfData = PDFGenerator.generate(for: report) {
            report.pdfData = pdfData
        }

        modelContext.insert(report)
        try? modelContext.save()

        isGenerating = false
    }
}

// MARK: - Row

struct ReportRowView: View {
    let report: MonthlyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.displayMonth)
                .font(.headline)
            Text("스크린샷 \(report.screenshots.count)개")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(ScreenshotCategory.allCases, id: \.self) { cat in
                    let count = report.screenshots.filter { $0.category == cat }.count
                    if count > 0 {
                        Label("\(count)", systemImage: cat.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
