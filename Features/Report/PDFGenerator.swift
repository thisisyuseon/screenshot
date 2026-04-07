import PDFKit
import UIKit
import SwiftUI

final class PDFGenerator {

    static func generate(for report: MonthlyReport) -> Data? {
        let pdfMetaData = [
            kCGPDFContextCreator: "SnapSort",
            kCGPDFContextAuthor: "SnapSort App",
            kCGPDFContextTitle: "\(report.displayMonth) 스크린샷 보고서"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageWidth: CGFloat = 595.2   // A4
        let pageHeight: CGFloat = 841.8
        let margin: CGFloat = 36
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        let data = renderer.pdfData { context in
            var yOffset: CGFloat = margin
            var currentPage = 0

            func newPageIfNeeded(neededHeight: CGFloat) {
                if yOffset + neededHeight > pageHeight - margin {
                    context.beginPage()
                    currentPage += 1
                    yOffset = margin
                }
            }

            // ── 표지 ──
            context.beginPage()

            let titleFont = UIFont.systemFont(ofSize: 28, weight: .bold)
            let subtitleFont = UIFont.systemFont(ofSize: 14, weight: .regular)
            let dateFont = UIFont.systemFont(ofSize: 12)

            let title = "\(report.displayMonth) 스크린샷 보고서"
            drawText(title, font: titleFont, at: CGPoint(x: margin, y: yOffset), width: contentWidth, color: .black)
            yOffset += 40

            let subtitle = "총 \(report.screenshots.count)개 스크린샷 · \(report.screenshots.filter(\.isProcessed).count)개 처리 완료"
            drawText(subtitle, font: subtitleFont, at: CGPoint(x: margin, y: yOffset), width: contentWidth, color: .darkGray)
            yOffset += 24

            let dateStr = "생성일: \(formattedDate(report.createdAt))"
            drawText(dateStr, font: dateFont, at: CGPoint(x: margin, y: yOffset), width: contentWidth, color: .gray)
            yOffset += 48

            // 구분선
            drawLine(from: CGPoint(x: margin, y: yOffset), to: CGPoint(x: pageWidth - margin, y: yOffset))
            yOffset += 24

            // ── 카테고리 요약 ──
            let sectionFont = UIFont.systemFont(ofSize: 18, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 12)
            let captionFont = UIFont.systemFont(ofSize: 10)

            drawText("카테고리 요약", font: sectionFont, at: CGPoint(x: margin, y: yOffset), width: contentWidth, color: .black)
            yOffset += 28

            for category in ScreenshotCategory.allCases {
                let items = report.screenshots.filter { $0.category == category && $0.isProcessed }
                let line = "\(category.rawValue): \(items.count)개"
                drawText(line, font: bodyFont, at: CGPoint(x: margin + 8, y: yOffset), width: contentWidth, color: .darkGray)
                yOffset += 18
            }

            yOffset += 16

            // ── 각 카테고리별 상세 ──
            for category in ScreenshotCategory.allCases {
                let items = report.screenshots.filter { $0.category == category && $0.isProcessed }
                guard !items.isEmpty else { continue }

                newPageIfNeeded(neededHeight: 60)
                drawLine(from: CGPoint(x: margin, y: yOffset), to: CGPoint(x: pageWidth - margin, y: yOffset), color: .lightGray)
                yOffset += 16

                drawText(category.rawValue, font: sectionFont, at: CGPoint(x: margin, y: yOffset), width: contentWidth, color: .black)
                yOffset += 28

                for item in items {
                    newPageIfNeeded(neededHeight: 80)

                    // 날짜 + 카테고리
                    let dateLabel = formattedDate(item.capturedAt)
                    drawText(dateLabel, font: captionFont, at: CGPoint(x: margin, y: yOffset), width: contentWidth, color: .gray)
                    yOffset += 14

                    // 요약
                    if !item.summary.isEmpty {
                        drawText(item.summary, font: bodyFont, at: CGPoint(x: margin + 8, y: yOffset), width: contentWidth - 8, color: .darkGray)
                        yOffset += 18
                    }

                    // 태그
                    if !item.tags.isEmpty {
                        let tagStr = item.tags.map { "#\($0)" }.joined(separator: " ")
                        drawText(tagStr, font: captionFont, at: CGPoint(x: margin + 8, y: yOffset), width: contentWidth - 8, color: .systemBlue)
                        yOffset += 14
                    }

                    // 메모
                    if !item.note.isEmpty {
                        drawText("메모: \(item.note)", font: captionFont, at: CGPoint(x: margin + 8, y: yOffset), width: contentWidth - 8, color: .systemGray)
                        yOffset += 14
                    }

                    // 썸네일
                    if let data = item.thumbnailData, let image = UIImage(data: data) {
                        let thumbHeight: CGFloat = 120
                        let thumbWidth = min(image.size.width / image.size.height * thumbHeight, 180)
                        newPageIfNeeded(neededHeight: thumbHeight + 16)
                        image.draw(in: CGRect(x: margin + 8, y: yOffset, width: thumbWidth, height: thumbHeight))
                        yOffset += thumbHeight + 8
                    }

                    yOffset += 8
                }
            }

            // ── 나중에 확인 체크리스트 ──
            let checklistItems = report.reviewLaterItems
            if !checklistItems.isEmpty {
                newPageIfNeeded(neededHeight: 60)
                context.beginPage()
                yOffset = margin

                drawText("나중에 확인 체크리스트", font: sectionFont, at: CGPoint(x: margin, y: yOffset), width: contentWidth, color: .black)
                yOffset += 32

                for item in checklistItems {
                    newPageIfNeeded(neededHeight: 30)
                    drawText("☐  \(item.summary.isEmpty ? "내용 없음" : item.summary)",
                             font: bodyFont,
                             at: CGPoint(x: margin, y: yOffset),
                             width: contentWidth,
                             color: .darkGray)
                    yOffset += 20
                }
            }
        }

        return data
    }

    // MARK: - Drawing Helpers

    private static func drawText(_ text: String, font: UIFont, at point: CGPoint, width: CGFloat, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let rect = CGRect(x: point.x, y: point.y, width: width, height: 1000)
        str.draw(in: rect)
    }

    private static func drawLine(from start: CGPoint, to end: CGPoint, color: UIColor = .black) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.5)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
    }
}
