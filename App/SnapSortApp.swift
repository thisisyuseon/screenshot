import SwiftUI
import SwiftData

@main
struct SnapSortApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ScreenshotItem.self,
            MonthlyReport.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("ModelContainer를 생성할 수 없습니다: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
