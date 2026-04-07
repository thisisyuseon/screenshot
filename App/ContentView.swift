import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("홈", systemImage: "house.fill")
                }

            ReviewView()
                .tabItem {
                    Label("리뷰", systemImage: "rectangle.on.rectangle.angled")
                }

            ReportListView()
                .tabItem {
                    Label("보고서", systemImage: "doc.text.fill")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ScreenshotItem.self, MonthlyReport.self], inMemory: true)
}
