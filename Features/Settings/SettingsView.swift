import SwiftUI
import UserNotifications

struct SettingsView: View {
    @StateObject private var claudeService = ClaudeService.shared
    @AppStorage("auto_notify_enabled") private var autoNotifyEnabled = false
    @AppStorage("notify_day") private var notifyDay: Int = 1
    @AppStorage("delete_policy") private var deletePolicy: DeletePolicy = .afterReport

    @State private var apiKeyInput: String = ""
    @State private var isApiKeyVisible = false
    @State private var showingApiKeyHelp = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    enum DeletePolicy: String, CaseIterable {
        case immediate = "리뷰 즉시 삭제"
        case afterReport = "보고서 생성 후 삭제"
        case manual = "수동으로 삭제"

        var description: String {
            switch self {
            case .immediate: return "리뷰에서 확인 완료 시 바로 삭제"
            case .afterReport: return "보고서를 만든 뒤 일괄 삭제"
            case .manual: return "보고서 상세에서 직접 삭제"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // API 키 섹션
                Section {
                    HStack {
                        if isApiKeyVisible {
                            TextField("sk-ant-...", text: $apiKeyInput)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("API 키 입력", text: $apiKeyInput)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        Button {
                            isApiKeyVisible.toggle()
                        } label: {
                            Image(systemName: isApiKeyVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("저장") {
                        claudeService.apiKey = apiKeyInput.trimmingCharacters(in: .whitespaces)
                        apiKeyInput = ""
                        hideKeyboard()
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !claudeService.apiKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("API 키가 저장되어 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Claude API 키")
                } footer: {
                    Button("API 키 발급 방법") {
                        showingApiKeyHelp = true
                    }
                    .font(.caption)
                }

                // 알림 설정
                Section("월간 정리 알림") {
                    Toggle("매월 알림 받기", isOn: $autoNotifyEnabled)
                        .onChange(of: autoNotifyEnabled) { _, newValue in
                            if newValue {
                                Task { await requestNotificationPermission() }
                            }
                        }

                    if autoNotifyEnabled {
                        Stepper("매월 \(notifyDay)일", value: $notifyDay, in: 1...28)
                    }
                }

                // 삭제 정책
                Section("스크린샷 삭제 정책") {
                    ForEach(DeletePolicy.allCases, id: \.self) { policy in
                        Button {
                            deletePolicy = policy
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(policy.rawValue)
                                        .foregroundStyle(.primary)
                                    Text(policy.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if deletePolicy == policy {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                // 앱 정보
                Section("앱 정보") {
                    LabeledContent("버전", value: appVersion)
                    LabeledContent("AI 모델", value: "Claude Haiku 4.5")

                    NavigationLink("개인정보 처리방침") {
                        PrivacyPolicyView()
                    }
                }

                // 데이터 초기화
                Section {
                    Button(role: .destructive) {
                        claudeService.apiKey = ""
                    } label: {
                        Label("API 키 삭제", systemImage: "key.slash")
                    }
                } header: {
                    Text("데이터")
                }
            }
            .navigationTitle("설정")
            .onAppear {
                apiKeyInput = ""
                Task { await checkNotificationStatus() }
            }
            .sheet(isPresented: $showingApiKeyHelp) {
                ApiKeyHelpView()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                scheduleMonthlyNotification()
            } else {
                autoNotifyEnabled = false
            }
        } catch {
            autoNotifyEnabled = false
        }
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func scheduleMonthlyNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["monthly_reminder"])

        var components = DateComponents()
        components.day = notifyDay
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "이번 달 스크린샷 정리 시간"
        content.body = "쌓인 스크린샷을 SnapSort로 정리해보세요."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "monthly_reminder", content: content, trigger: trigger)
        center.add(request)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - API Key Help

struct ApiKeyHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Claude API 키 발급 방법")
                        .font(.title2.bold())

                    Group {
                        stepView(number: 1, text: "console.anthropic.com 에 접속하세요.")
                        stepView(number: 2, text: "계정이 없다면 회원가입 후 로그인하세요.")
                        stepView(number: 3, text: "좌측 메뉴에서 'API Keys'를 선택하세요.")
                        stepView(number: 4, text: "'Create Key' 버튼을 눌러 키를 생성하세요.")
                        stepView(number: 5, text: "생성된 키(sk-ant-...)를 복사해서 설정에 붙여넣으세요.")
                    }

                    Text("참고: API 사용량에 따라 요금이 부과됩니다. 스크린샷 분류에는 가장 저렴한 Haiku 모델을 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(Color.yellow.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
            .navigationTitle("API 키 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func stepView(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                **개인정보 처리방침**

                SnapSort는 다음과 같은 방식으로 데이터를 처리합니다:

                **수집 정보**
                - 스크린샷 이미지 및 메타데이터 (촬영일시)
                - OCR로 추출된 텍스트
                - AI 분류 결과

                **데이터 저장**
                - 모든 데이터는 기기 내에 저장됩니다.
                - 서버에 업로드되는 정보는 없습니다.

                **Claude API 사용**
                - 분류를 위해 OCR 텍스트와 썸네일이 Anthropic API로 전송됩니다.
                - Anthropic의 개인정보 처리방침이 적용됩니다.

                **사진 접근**
                - 스크린샷 조회 및 삭제에만 사용됩니다.
                """)
                .padding()
            }
        }
        .navigationTitle("개인정보 처리방침")
        .navigationBarTitleDisplayMode(.inline)
    }
}
