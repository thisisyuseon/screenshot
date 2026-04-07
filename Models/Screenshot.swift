import Foundation
import SwiftData

enum ScreenshotCategory: String, Codable, CaseIterable {
    case reviewLater = "나중에 확인"
    case inspiration = "영감"
    case info = "정보/지식"
    case other = "기타"

    var icon: String {
        switch self {
        case .reviewLater: return "bookmark.fill"
        case .inspiration: return "lightbulb.fill"
        case .info: return "doc.text.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var color: String {
        switch self {
        case .reviewLater: return "blue"
        case .inspiration: return "yellow"
        case .info: return "green"
        case .other: return "gray"
        }
    }
}

@Model
final class ScreenshotItem {
    var id: UUID
    var localIdentifier: String
    var capturedAt: Date
    var ocrText: String
    var category: ScreenshotCategory
    var summary: String
    var tags: [String]
    var note: String
    var isProcessed: Bool
    var isDeletedFromLibrary: Bool
    var reportMonth: String  // "2026-04"
    var thumbnailData: Data?

    init(
        localIdentifier: String,
        capturedAt: Date,
        reportMonth: String
    ) {
        self.id = UUID()
        self.localIdentifier = localIdentifier
        self.capturedAt = capturedAt
        self.ocrText = ""
        self.category = .other
        self.summary = ""
        self.tags = []
        self.note = ""
        self.isProcessed = false
        self.isDeletedFromLibrary = false
        self.reportMonth = reportMonth
    }
}

@Model
final class MonthlyReport {
    var id: UUID
    var month: String  // "2026-04"
    var createdAt: Date
    var totalCount: Int
    var pdfData: Data?

    @Relationship(deleteRule: .nullify)
    var screenshots: [ScreenshotItem]

    init(month: String) {
        self.id = UUID()
        self.month = month
        self.createdAt = Date()
        self.totalCount = 0
        self.screenshots = []
    }

    var reviewLaterItems: [ScreenshotItem] {
        screenshots.filter { $0.category == .reviewLater }
    }

    var inspirationItems: [ScreenshotItem] {
        screenshots.filter { $0.category == .inspiration }
    }

    var infoItems: [ScreenshotItem] {
        screenshots.filter { $0.category == .info }
    }

    var otherItems: [ScreenshotItem] {
        screenshots.filter { $0.category == .other }
    }

    var displayMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: month) {
            formatter.dateFormat = "yyyy년 M월"
            return formatter.string(from: date)
        }
        return month
    }
}
