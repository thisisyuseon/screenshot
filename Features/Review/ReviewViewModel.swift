import SwiftUI
import SwiftData

@MainActor
final class ReviewViewModel: ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var showingDeleteConfirm = false
    @Published var isDeleting = false
    @Published var errorMessage: String?
    @Published var showingError = false

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func confirmItem(_ item: ScreenshotItem, category: ScreenshotCategory, note: String) {
        item.category = category
        item.note = note
        item.isProcessed = true
        try? modelContext.save()
        currentIndex += 1
    }

    func skipItem(_ item: ScreenshotItem) {
        // 삭제 없이 건너뜀 (isProcessed = false 유지)
        currentIndex += 1
    }

    func deleteFromLibraryAndConfirm(_ item: ScreenshotItem, category: ScreenshotCategory, note: String) async {
        item.category = category
        item.note = note
        item.isProcessed = true

        do {
            try await PhotosService.shared.deleteAssets(identifiers: [item.localIdentifier])
            item.isDeletedFromLibrary = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }

        try? modelContext.save()
        currentIndex += 1
    }
}
