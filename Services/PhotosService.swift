import Photos
import UIKit

enum PhotosError: Error, LocalizedError {
    case accessDenied
    case fetchFailed
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "사진 라이브러리 접근 권한이 없습니다. 설정에서 허용해주세요."
        case .fetchFailed:
            return "스크린샷을 불러오지 못했습니다."
        case .deletionFailed(let reason):
            return "삭제 실패: \(reason)"
        }
    }
}

struct ScreenshotAsset {
    let localIdentifier: String
    let capturedAt: Date
    let asset: PHAsset
}

@MainActor
final class PhotosService: ObservableObject {

    static let shared = PhotosService()

    // MARK: - Authorization

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status
    }

    var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - Fetch Screenshots

    /// 지정 기간의 스크린샷을 모두 가져옴
    func fetchScreenshots(from startDate: Date, to endDate: Date) async throws -> [ScreenshotAsset] {
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw PhotosError.accessDenied
        }

        return try await Task.detached(priority: .userInitiated) {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(
                format: "mediaSubtype == %d AND creationDate >= %@ AND creationDate <= %@",
                PHAssetMediaSubtype.photoScreenshot.rawValue,
                startDate as CVarArg,
                endDate as CVarArg
            )
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var assets: [ScreenshotAsset] = []

            result.enumerateObjects { asset, _, _ in
                assets.append(ScreenshotAsset(
                    localIdentifier: asset.localIdentifier,
                    capturedAt: asset.creationDate ?? Date(),
                    asset: asset
                ))
            }
            return assets
        }.value
    }

    /// 이번 달 스크린샷
    func fetchThisMonthScreenshots() async throws -> [ScreenshotAsset] {
        let (start, end) = currentMonthRange()
        return try await fetchScreenshots(from: start, to: end)
    }

    /// 지난 달 스크린샷
    func fetchLastMonthScreenshots() async throws -> [ScreenshotAsset] {
        let (start, end) = lastMonthRange()
        return try await fetchScreenshots(from: start, to: end)
    }

    // MARK: - Thumbnail

    func loadThumbnail(for asset: PHAsset, targetSize: CGSize = CGSize(width: 300, height: 300)) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Delete

    /// 처리된 스크린샷 일괄 삭제
    func deleteAssets(identifiers: [String]) async throws {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetsToDelete: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assetsToDelete.append(asset)
        }

        guard !assetsToDelete.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotosError.deletionFailed(error?.localizedDescription ?? "알 수 없는 오류"))
                }
            }
        }
    }

    // MARK: - Date Range Helpers

    func currentMonthRange() -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)!
        return (start, end)
    }

    func lastMonthRange() -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()
        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
        let lastMonthEnd = calendar.date(byAdding: DateComponents(second: -1), to: thisMonthStart)!
        return (lastMonthStart, lastMonthEnd)
    }

    func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
