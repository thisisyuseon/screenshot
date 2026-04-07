import Foundation
import UIKit

// MARK: - Request / Response Models

struct ClaudeClassifyRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

struct ClaudeMessage: Encodable {
    let role: String
    let content: [ClaudeContent]
}

struct ClaudeContent: Encodable {
    let type: String
    let text: String?
    let source: ClaudeImageSource?

    init(text: String) {
        self.type = "text"
        self.text = text
        self.source = nil
    }

    init(imageSource: ClaudeImageSource) {
        self.type = "image"
        self.text = nil
        self.source = imageSource
    }
}

struct ClaudeImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

struct ClaudeResponse: Decodable {
    let content: [ClaudeResponseContent]
}

struct ClaudeResponseContent: Decodable {
    let type: String
    let text: String?
}

struct ClassificationResult {
    let category: ScreenshotCategory
    let summary: String
    let tags: [String]
}

// MARK: - Service

enum ClaudeError: Error, LocalizedError {
    case apiKeyMissing
    case networkError(String)
    case invalidResponse
    case parseError(String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Claude API 키가 설정되지 않았습니다. 설정에서 입력해주세요."
        case .networkError(let msg):
            return "네트워크 오류: \(msg)"
        case .invalidResponse:
            return "API 응답을 처리할 수 없습니다."
        case .parseError(let msg):
            return "응답 파싱 실패: \(msg)"
        case .rateLimited:
            return "API 요청 한도 초과. 잠시 후 다시 시도해주세요."
        }
    }
}

@MainActor
final class ClaudeService: ObservableObject {

    static let shared = ClaudeService()

    private let apiURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5-20251001"

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "claude_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "claude_api_key") }
    }

    private let systemPrompt = """
    당신은 스크린샷 내용을 분류하는 도우미입니다.
    다음 카테고리 중 하나로만 분류하세요:
    - reviewLater: 나중에 확인이 필요한 정보 (링크, 가격, 할 일, 예약 정보 등)
    - inspiration: 영감을 주는 콘텐츠 (디자인, 글귀, 아이디어, 예술 등)
    - info: 유용한 정보/지식 (뉴스, 레시피, 튜토리얼, 설명 등)
    - other: 위 카테고리에 해당하지 않는 내용

    반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트는 포함하지 마세요:
    {"category": "reviewLater|inspiration|info|other", "summary": "1-2문장 요약", "tags": ["태그1", "태그2"]}
    """

    // MARK: - Classify

    func classify(ocrText: String, thumbnail: UIImage? = nil) async throws -> ClassificationResult {
        guard !apiKey.isEmpty else {
            throw ClaudeError.apiKeyMissing
        }

        var contents: [ClaudeContent] = []

        // 이미지가 있으면 포함 (썸네일)
        if let thumbnail,
           let imageData = thumbnail.jpegData(compressionQuality: 0.5) {
            let base64 = imageData.base64EncodedString()
            contents.append(ClaudeContent(imageSource: ClaudeImageSource(
                type: "base64",
                mediaType: "image/jpeg",
                data: base64
            )))
        }

        let userText: String
        if ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userText = "이 스크린샷의 내용을 분석하고 JSON으로 분류해주세요. OCR 텍스트가 없습니다."
        } else {
            userText = """
            다음 스크린샷의 OCR 텍스트를 분석하고 JSON으로 분류해주세요.

            OCR 텍스트:
            \(ocrText.prefix(2000))
            """
        }
        contents.append(ClaudeContent(text: userText))

        let requestBody = ClaudeClassifyRequest(
            model: model,
            maxTokens: 256,
            system: systemPrompt,
            messages: [ClaudeMessage(role: "user", content: contents)]
        )

        let responseText = try await sendRequest(requestBody)
        return try parseClassificationResult(from: responseText)
    }

    // MARK: - Batch Processing

    func classifyBatch(
        items: [(ocrText: String, thumbnail: UIImage?)],
        onProgress: @escaping (Int, Int) -> Void
    ) async -> [Result<ClassificationResult, Error>] {
        var results: [Result<ClassificationResult, Error>] = []

        for (index, item) in items.enumerated() {
            do {
                let result = try await classify(ocrText: item.ocrText, thumbnail: item.thumbnail)
                results.append(.success(result))
            } catch {
                results.append(.failure(error))
            }

            onProgress(index + 1, items.count)

            // API 과부하 방지: 요청 간 0.3초 대기
            if index < items.count - 1 {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        return results
    }

    // MARK: - Private

    private func sendRequest(_ requestBody: ClaudeClassifyRequest) async throws -> String {
        let url = URL(string: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 429:
            throw ClaudeError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.networkError("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeError.invalidResponse
        }
        return text
    }

    private func parseClassificationResult(from text: String) throws -> ClassificationResult {
        // JSON만 추출 (마크다운 코드 블록 제거)
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonStart = cleaned.firstIndex(of: "{"),
              let jsonEnd = cleaned.lastIndex(of: "}") else {
            throw ClaudeError.parseError("JSON을 찾을 수 없습니다: \(text)")
        }

        let jsonString = String(cleaned[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClaudeError.parseError("JSON 변환 실패")
        }

        struct RawResult: Decodable {
            let category: String
            let summary: String
            let tags: [String]
        }

        let raw = try JSONDecoder().decode(RawResult.self, from: jsonData)

        let category: ScreenshotCategory
        switch raw.category {
        case "reviewLater": category = .reviewLater
        case "inspiration": category = .inspiration
        case "info": category = .info
        default: category = .other
        }

        return ClassificationResult(
            category: category,
            summary: raw.summary,
            tags: raw.tags
        )
    }
}
