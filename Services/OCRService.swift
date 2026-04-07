import Vision
import UIKit

enum OCRError: Error, LocalizedError {
    case imageLoadFailed
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "이미지를 불러오지 못했습니다."
        case .recognitionFailed(let reason):
            return "텍스트 인식 실패: \(reason)"
        }
    }
}

final class OCRService {

    static let shared = OCRService()

    /// UIImage에서 텍스트 추출
    func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.imageLoadFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    /// Data에서 텍스트 추출
    func recognizeText(from imageData: Data) async throws -> String {
        guard let image = UIImage(data: imageData) else {
            throw OCRError.imageLoadFailed
        }
        return try await recognizeText(from: image)
    }

    /// 텍스트가 있는지 빠르게 확인 (분류 전 필터링용)
    func hasText(in image: UIImage) async -> Bool {
        guard let text = try? await recognizeText(from: image) else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
