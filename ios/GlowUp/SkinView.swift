import SwiftUI

// MARK: - ViewModel
final class SkinPageViewModel: ObservableObject {
    @Published var page: SkinPageResponse?
    @Published var isLoading = false
    @Published var error: String?
    @Published var completedSteps: Set<String> = []
    
    var profile: SkinPageProfile? { page?.profile }
    var routine: SkinPageRoutine? { page?.routine }
    var insights: SkinPageInsights? { page?.insights }
    var streaks: SkinPageStreaks? { page?.streaks }
    var agent: SkinPageAgent? { page?.agent }
    
    var morningSteps: [SkinPageRoutineStep] { routine?.morning ?? [] }
    var eveningSteps: [SkinPageRoutineStep] { routine?.evening ?? [] }
    
    var skinScore: Double {
        let raw = insights?.skin_score ?? 0.85
        return raw > 1 ? min(raw / 100, 1.0) : max(raw, 0)
    }
    
    func load(userId: String?, forceRefresh: Bool = false) {
        guard let userId, !isLoading else { return }
        isLoading = true
        error = nil
        
        Task {
            do {
                let result = try await APIService.shared.fetchSkinPage(userId: userId, forceRefresh: forceRefresh)
                await MainActor.run {
                    self.page = result
                    self.completedSteps = Set(result.today_checkins)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.error = "Couldn't load your profile"
                }
            }
        }
    }
    
    func stepKey(_ step: SkinPageRoutineStep, routineType: String) -> String {
        // Match the format used by HomeView: "routineType:step.id" where id = "\(step)-\(name)"
        return "\(routineType):\(step.step)-\(step.name)"
    }
    
    func toggleStep(_ step: SkinPageRoutineStep, routineType: String) {
        guard let userId = SessionManager.shared.userId else { return }
        let key = stepKey(step, routineType: routineType)
        let stepId = step.id // e.g. "1-Cleanser"
        let wasCompleted = completedSteps.contains(key)
        
        // Optimistic update
        if wasCompleted {
            completedSteps.remove(key)
        } else {
            completedSteps.insert(key)
        }
        
        Task {
            do {
                if wasCompleted {
                    _ = try await APIService.shared.markStepIncomplete(userId: userId, routineType: routineType, stepId: stepId)
                } else {
                    _ = try await APIService.shared.markStepComplete(userId: userId, routineType: routineType, stepId: stepId, stepName: step.name)
                }
            } catch {
                // Revert on error
                await MainActor.run {
                    if wasCompleted {
                        completedSteps.insert(key)
                    } else {
                        completedSteps.remove(key)
                    }
                }
            }
        }
    }
}

struct GlowProgressSnapshot: Codable, Identifiable {
    let id: String          // yyyy-MM-dd (one snapshot per day)
    let recordedAt: Date
    let score: Int
    let completedSteps: Int
    let totalSteps: Int
    let morningStreak: Int
    let eveningStreak: Int

    var completionRate: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }
}

// MARK: - Main View
struct SkinView: View {
    @StateObject private var viewModel = SkinPageViewModel()
    @State private var selectedTab: SkinTab = .routine
    @State private var showRoutineDetail = false
    @State private var selectedRoutineType: String = "morning"
    @State private var showPaywall = false
    @State private var routineEditorType: HomeView.RoutineType?
    @State private var routineStreaks: (morning: Int, evening: Int) = (0, 0)
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var sharePreview: RoutineSharePreviewData?
    @State private var isPreparingShare = false
    @State private var shareError: String?
    @State private var routineLibrary: [SessionManager.RoutineLibraryItem] = SessionManager.shared.routineLibrary
    @State private var isImportingSharedRoutine = false
    @State private var isApplyingLibraryRoutine = false
    @State private var libraryStatusMessage: String?
    @State private var libraryStatusIsError = false
    @State private var routineKeyInput = ""
    @State private var showAddRoutineModal = false
    @State private var progressHistory: [GlowProgressSnapshot] = []
    
    enum SkinTab: String, CaseIterable {
        case routine = "My Routine"
        case profile = "Profile"
        case progress = "Progress"
    }
    
    private var skinToneBackgroundImageName: String {
        guard let value = viewModel.profile?.skin_tone_value else { return "lightskin_black" }
        if value < 0.35 { return "white" }
        if value < 0.70 { return "lightskin_black" }
        return "black"
    }

    var body: some View {
        skinRootContent
            .background(
                ZStack(alignment: .top) {
                    PinkDrapeBackground().ignoresSafeArea()
                    
                    if let _ = viewModel.page {
                        GeometryReader { proxy in
                            Image(skinToneBackgroundImageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: proxy.size.width, height: proxy.size.height * 0.45)
                                .clipped()
                                .mask(
                                    LinearGradient(
                                        colors: [.black, .black.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .opacity(0.15)
                        }
                    }
                }
                .ignoresSafeArea()
            )
            .refreshable {
                viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
            }
            .onAppear(perform: handleOnAppear)
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView()
            }
            .sheet(item: $routineEditorType) { routineType in
                RoutineDetailSheet(
                    routineType: routineType,
                    steps: feedRoutineSteps(for: routineType),
                    morningSteps: feedRoutineSteps(for: .morning),
                    eveningSteps: feedRoutineSteps(for: .evening),
                    weeklySteps: [],
                    completedSteps: completedStepsBinding,
                    streaks: $routineStreaks,
                    userId: SessionManager.shared.userId ?? "",
                    onRoutineUpdated: {
                        viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
                    }
                )
            }
            .sheet(isPresented: $showAddRoutineModal) {
                addRoutineModalContent
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityShareSheet(items: shareItems)
            }
            .overlay {
                if let sharePreview {
                    RoutineSharePreviewModal(
                        preview: sharePreview,
                        onClose: { self.sharePreview = nil },
                        onShare: { handleSharePreviewShare(sharePreview) }
                    )
                    .zIndex(2)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .glowUpNotificationDestination)) { note in
                handleDestinationNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .glowUpOpenRoutineImport)) { note in
                handleRoutineImportNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .glowUpRoutineDidUpdate)) { _ in
                viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
            }
            .onChange(of: viewModel.page?.streaks.morning ?? 0) { _, newVal in
                handleMorningStreakChange(newVal)
            }
            .onChange(of: viewModel.page?.streaks.evening ?? 0) { _, newVal in
                handleEveningStreakChange(newVal)
            }
            .onChange(of: viewModel.completedSteps.count) { _, _ in
                recordProgressSnapshot()
            }
            .onChange(of: viewModel.page?.insights.skin_score ?? -1) { _, _ in
                recordProgressSnapshot()
            }
    }

    private var skinRootContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if viewModel.isLoading && viewModel.page == nil {
                    loadingState
                } else if let _ = viewModel.page {
                    // Header
                    headerSection
                    
                    // Score + Quick Stats
                    scoreCard
                    
                    // Tab Picker
                    tabPicker
                    
                    // Content
                    selectedTabContent
                } else if viewModel.error != nil {
                    errorState
                }
                
                Spacer().frame(height: 120)
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .routine:
            routineContent
        case .profile:
            profileContent
        case .progress:
            progressContent
        }
    }

    private var completedStepsBinding: Binding<Set<String>> {
        Binding(
            get: { viewModel.completedSteps },
            set: { viewModel.completedSteps = $0 }
        )
    }

    private func handleOnAppear() {
        if viewModel.page == nil {
            viewModel.load(userId: SessionManager.shared.userId)
        }
        routineLibrary = SessionManager.shared.routineLibrary
        consumePendingSharedRoutineTokenIfNeeded()
        loadProgressHistory()
        recordProgressSnapshot()
    }

    private func handleSharePreviewShare(_ preview: RoutineSharePreviewData) {
        shareItems = preview.shareItems
        sharePreview = nil
        showShareSheet = true
    }

    private func handleDestinationNotification(_ note: Notification) {
        guard let destination = note.userInfo?["destination"] as? String else { return }
        if destination == "routine" {
            selectedTab = .routine
        } else if destination == "progress" {
            selectedTab = .progress
        }
    }

    private func handleRoutineImportNotification(_ note: Notification) {
        if let token = note.userInfo?["token"] as? String, !token.isEmpty {
            importSharedRoutine(token: token)
        } else {
            consumePendingSharedRoutineTokenIfNeeded()
        }
    }

    private func handleMorningStreakChange(_ newValue: Int) {
        routineStreaks.morning = newValue
        recordProgressSnapshot()
    }

    private func handleEveningStreakChange(_ newValue: Int) {
        routineStreaks.evening = newValue
        recordProgressSnapshot()
    }
    
    // MARK: - Loading
    private var loadingState: some View {
        VStack(spacing: 20) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.6))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, Color.white.opacity(0.4), Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }
    
    private var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: "FF6B9D"))
            Text(viewModel.error ?? "Something went wrong")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "666666"))
            Button("Retry") {
                viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color(hex: "FF6B9D"))
            .cornerRadius(12)
        }
        .padding(40)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.agent?.page_title ?? "Your Glow")
                        .font(.custom("Didot", size: 33))
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "232327"))
                    Text(viewModel.agent?.page_subtitle ?? "Personalized care for your skin")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "7D7D85"))
                        .lineLimit(2)
                }

                Spacer()

                Button(action: {
                    viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "FF5C95"))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Circle())
                }
            }

            HStack(spacing: 8) {
                Label(viewModel.profile?.skin_type.capitalized ?? "Normal", systemImage: "drop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "FF5C95"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.85))
                    .cornerRadius(14)
                Label("Score \(Int(viewModel.skinScore * 100))", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "5B5B62"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.85))
                    .cornerRadius(14)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFEAF3"), Color(hex: "FFF7FB")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .cornerRadius(22)
        .shadow(color: Color(hex: "D8C9D2").opacity(0.3), radius: 14, x: 0, y: 8)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Score Card
    private var scoreCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                // Score Ring
                ZStack {
                    Circle()
                        .stroke(Color(hex: "F2E7EE"), lineWidth: 9)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: viewModel.skinScore)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "FF5C95"), Color(hex: "FF98B7")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8), value: viewModel.skinScore)
                    
                    VStack(spacing: 2) {
                        Text("\(Int(viewModel.skinScore * 100))")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color(hex: "252529"))
                        Text("Score")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "9B9BA2"))
                    }
                }
                
                // Profile Quick Info
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "FF5C95"))
                        Text("Skin Type")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "94949A"))
                    }
                    Text(viewModel.profile?.skin_type.capitalized ?? "Normal")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "FF5C95"))
                        Text("Focus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "94949A"))
                    }
                    Text(viewModel.agent?.weekly_focus ?? "Consistency")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "FF5C95"))
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            // Quick Stats Row
            HStack(spacing: 12) {
                QuickStat(
                    icon: "drop.fill",
                    label: "Hydration",
                    value: viewModel.insights?.hydration ?? "—",
                    color: Color(hex: "4ECDC4")
                )
                QuickStat(
                    icon: "sun.max.fill",
                    label: "Protection",
                    value: viewModel.insights?.protection ?? "—",
                    color: Color(hex: "FFB800")
                )
                QuickStat(
                    icon: "sparkles",
                    label: "Texture",
                    value: viewModel.insights?.texture ?? "—",
                    color: Color(hex: "9B6BFF")
                )
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 8)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Tab Picker
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(SkinTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedTab == tab ? Color(hex: "FF5C95") : Color(hex: "8D8D94"))
                        Capsule()
                            .fill(selectedTab == tab ? Color(hex: "FF5C95") : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .background(Color.white.opacity(0.85))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Routine Content
    private var routineContent: some View {
        VStack(spacing: 18) {
            routineKeyImportSection

            if let shareError {
                Text(shareError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "D64545"))
            }

            if !routineLibrary.isEmpty {
                routineLibrarySection
            }

            // Agent Assessment
            if let assessment = viewModel.agent?.skin_assessment, !assessment.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "FF6B9D"))
                    
                    Text(assessment)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "555555"))
                        .lineSpacing(4)
                }
                .padding(16)
                .background(Color(hex: "FFF5F8"))
                .cornerRadius(14)
            }
            
            // Morning Routine
            if !viewModel.morningSteps.isEmpty {
                routineSection(
                    title: "Morning Glow",
                    icon: "sun.max.fill",
                    color: Color(hex: "FFB800"),
                    steps: viewModel.morningSteps,
                    routineType: "morning"
                )
            }
            
            // Evening Routine
            if !viewModel.eveningSteps.isEmpty {
                routineSection(
                    title: "Evening Repair",
                    icon: "moon.fill",
                    color: Color(hex: "9B6BFF"),
                    steps: viewModel.eveningSteps,
                    routineType: "evening"
                )
            }
            
            // Empty State
            if viewModel.morningSteps.isEmpty && viewModel.eveningSteps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "FFB4C8"))
                    Text("Your routine is being crafted")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "666666"))
                    Text("Complete photo onboarding to unlock your personalized glow-up techniques and product recommendations.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "999999"))
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(16)
            }
        }
        .padding(.horizontal, 20)
    }

    private var routineKeyImportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: { showAddRoutineModal = true }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "FFE4EC"))
                            .frame(width: 34, height: 34)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Routine")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        Text("Import from a routine key")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "888888"))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "AAAAAA"))
                }
            }
            .buttonStyle(.plain)

            if let libraryStatusMessage {
                Text(libraryStatusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(libraryStatusIsError ? Color(hex: "D64545") : Color(hex: "3B8F68"))
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private var addRoutineModalContent: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter a routine key from another user to save it in your Routine Library.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "666666"))

                HStack(spacing: 8) {
                    TextField("Enter routine key", text: $routineKeyInput)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(hex: "EEDCE5"), lineWidth: 1)
                        )

                    Button(action: importRoutineUsingTypedKey) {
                        HStack(spacing: 6) {
                            if isImportingSharedRoutine {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "tray.and.arrow.down.fill")
                            }
                            Text("Add")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(hex: "FF6B9D"))
                        .cornerRadius(10)
                    }
                    .disabled(isImportingSharedRoutine || normalizedTypedRoutineKey.count < 6)
                }

                Text("Keys use only letters and numbers.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "999999"))

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(PinkDrapeBackground().ignoresSafeArea())
            .navigationTitle("Add Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showAddRoutineModal = false }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func routineSection(title: String, icon: String, color: Color, steps: [SkinPageRoutineStep], routineType: String) -> some View {
        let doneCount = completedRoutineCount(steps: steps, routineType: routineType)
        let completionTint = doneCount == steps.count ? Color(hex: "3B8F68") : Color(hex: "8E8E95")

        return VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Spacer()
                
                Text("\(doneCount)/\(steps.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(completionTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "F5F5F7"))
                    .cornerRadius(8)

                Button(action: { prepareRoutineShare(routineType: routineType, fallbackTitle: title, fallbackSteps: steps) }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isPreparingShare ? Color(hex: "B5B5B5") : Color(hex: "6D6D73"))
                        .padding(7)
                        .background(Color(hex: "F3F3F6"))
                        .clipShape(Circle())
                }
                .disabled(isPreparingShare)

                Button(action: {
                    routineEditorType = routineType == "morning" ? .morning : .evening
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "FF5C95"))
                        .padding(7)
                        .background(Color(hex: "FFEAF2"))
                        .clipShape(Circle())
                }
            }
            
            // Steps
            VStack(spacing: 10) {
                ForEach(steps) { step in
                    SkinRoutineStepRow(
                        step: step,
                        isCompleted: viewModel.completedSteps.contains(viewModel.stepKey(step, routineType: routineType)),
                        accentColor: color,
                        onToggle: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            viewModel.toggleStep(step, routineType: routineType)
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func completedRoutineCount(steps: [SkinPageRoutineStep], routineType: String) -> Int {
        steps.filter { step in
            viewModel.completedSteps.contains(viewModel.stepKey(step, routineType: routineType))
        }.count
    }

    private var routineLibrarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Routine Library")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                Spacer()
                if isImportingSharedRoutine {
                    ProgressView()
                        .scaleEffect(0.85)
                }
            }

            if let libraryStatusMessage {
                Text(libraryStatusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(libraryStatusIsError ? Color(hex: "D64545") : Color(hex: "3B8F68"))
            }

            ForEach(routineLibrary.prefix(5)) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                            .lineLimit(1)
                        Spacer()
                        Text(item.importedAt, style: .date)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "999999"))
                    }

                    HStack(spacing: 10) {
                        Label("AM \(item.morning.count)", systemImage: "sun.max.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "D29A00"))
                        Label("PM \(item.evening.count)", systemImage: "moon.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "8A6CF3"))
                    }

                    HStack(spacing: 8) {
                        Button(action: { applyRoutineLibraryItem(item) }) {
                            Text("Apply Morning + Night")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(hex: "FF6B9D"))
                                .cornerRadius(10)
                        }
                        .disabled(isApplyingLibraryRoutine)

                        Button(action: {
                            SessionManager.shared.removeRoutineLibraryItem(id: item.id)
                            routineLibrary = SessionManager.shared.routineLibrary
                        }) {
                            Text("Remove")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "777777"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(hex: "F2F2F2"))
                                .cornerRadius(10)
                        }
                        .disabled(isApplyingLibraryRoutine)
                    }
                }
                .padding(12)
                .background(Color(hex: "FBF8FC"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "F1E8EE"), lineWidth: 1)
                )
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Profile Content
    private var profileContent: some View {
        let skinGoals = formattedGoals(viewModel.profile?.skin_goals ?? [])
        let skinConcerns = formattedConcerns(viewModel.profile?.skin_concerns ?? [])
        let hairConcerns = formattedConcerns(viewModel.profile?.hair_concerns ?? [])

        return VStack(spacing: 14) {
            // Skin Info Card
            VStack(alignment: .leading, spacing: 14) {
                Text("Your Skin Profile")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                profileRow(icon: "drop.fill", label: "Skin Type", value: viewModel.profile?.skin_type.capitalized ?? "—", color: "FF6B9D")
                profileRow(icon: "circle.lefthalf.filled", label: "Skin Tone", value: viewModel.profile?.skin_tone ?? "—", color: "C68642")
                profileRow(icon: "sun.max.fill", label: "Sunscreen", value: formatSunscreen(viewModel.profile?.sunscreen_usage), color: "FFB800")
                profileRow(icon: "leaf.fill", label: "Fragrance-Free", value: (viewModel.profile?.fragrance_free ?? false) ? "Yes" : "No", color: "4ECDC4")
                profileRow(icon: "dollarsign.circle.fill", label: "Budget", value: viewModel.profile?.budget.capitalized ?? "—", color: "9B6BFF")
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(16)
            
            // Goals
            if !skinGoals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Goals")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    FlowLayoutView(items: skinGoals) { goal in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "4ECDC4"))
                            Text(goal)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "2D2D2D"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(hex: "E8FAF8"))
                        .cornerRadius(20)
                    }
                }
                .padding(18)
                .background(Color.white)
                .cornerRadius(16)
            }
            
            // Concerns
            if !skinConcerns.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Concerns")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    FlowLayoutView(items: skinConcerns) { concern in
                        Text(concern)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(hex: "FF6B9D"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "FFE4EC"))
                            .cornerRadius(20)
                    }
                }
                .padding(18)
                .background(Color.white)
                .cornerRadius(16)
            }
            
            // Hair Info (if available)
            if let hairType = viewModel.profile?.hair_type, !hairType.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Hair Profile")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    profileRow(icon: "scissors", label: "Hair Type", value: hairType.capitalized, color: "FF8FB1")
                    
                    if let wash = viewModel.profile?.wash_frequency {
                        profileRow(icon: "drop.triangle.fill", label: "Wash Frequency", value: formatWashFrequency(wash), color: "4ECDC4")
                    }
                    
                    if !hairConcerns.isEmpty {
                        FlowLayoutView(items: hairConcerns) { concern in
                            Text(concern)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "FF8FB1"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(hex: "FFE4EC"))
                                .cornerRadius(16)
                        }
                    }
                }
                .padding(18)
                .background(Color.white)
                .cornerRadius(16)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func profileRow(icon: String, label: String, value: String, color: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: color))
                .frame(width: 28)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "888888"))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "2D2D2D"))
        }
    }
    
    // MARK: - Progress Content
    private var progressContent: some View {
        let history = progressHistory.sorted { $0.recordedAt < $1.recordedAt }
        let recent = Array(history.suffix(8))
        let timeline = Array(recent.reversed())
        let latest = history.last
        let first = history.first
        let scoreDelta = (latest?.score ?? 0) - (first?.score ?? 0)
        let averageCompletion = history.isEmpty ? 0 : history.map { $0.completionRate }.reduce(0, +) / Double(history.count)
        let bestStreak = history.map { max($0.morningStreak, $0.eveningStreak) }.max() ?? 0

        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("GlowUp Progress Tracker")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                Text("Track your score, consistency, and streak trend over time.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "7E7E86"))

                HStack(spacing: 10) {
                    progressMetricCard(
                        title: "Score Change",
                        value: "\(scoreDelta >= 0 ? "+" : "")\(scoreDelta)",
                        tint: scoreDelta >= 0 ? Color(hex: "3B8F68") : Color(hex: "D64545")
                    )
                    progressMetricCard(
                        title: "Avg Consistency",
                        value: "\(Int((averageCompletion * 100).rounded()))%",
                        tint: Color(hex: "5B86FF")
                    )
                    progressMetricCard(
                        title: "Best Streak",
                        value: "\(bestStreak)d",
                        tint: Color(hex: "FF8E3C")
                    )
                }
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(16)

            VStack(alignment: .leading, spacing: 12) {
                Text("Score Trend")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))

                if history.isEmpty {
                    Text("No progress snapshots yet. Complete steps and check in daily.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "8F8F96"))
                } else {
                    ProgressTrendBars(snapshots: recent)
                }
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(16)

            VStack(alignment: .leading, spacing: 12) {
                Text("Timeline")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))

                if history.isEmpty {
                    Text("Your timeline will populate as you keep using your routine.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "8F8F96"))
                } else {
                    ForEach(timeline) { snapshot in
                        progressTimelineRow(snapshot)
                    }
                }
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(16)
        }
        .padding(.horizontal, 20)
    }

    private func progressTimelineRow(_ snapshot: GlowProgressSnapshot) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: "FF6B9D").opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(progressDateLabel(snapshot.recordedAt))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "2F2F33"))
                Text(progressTimelineSubtitle(snapshot))
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "7D7D85"))
            }

            Spacer()
        }
        .padding(10)
        .background(Color(hex: "FAF8FB"))
        .cornerRadius(12)
    }

    private var progressHistoryKey: String {
        "com.glowup.progressHistory.\(SessionManager.shared.userId ?? "guest")"
    }

    private func loadProgressHistory() {
        guard let data = UserDefaults.standard.data(forKey: progressHistoryKey),
              let decoded = try? JSONDecoder().decode([GlowProgressSnapshot].self, from: data) else {
            progressHistory = []
            return
        }
        progressHistory = decoded.sorted { $0.recordedAt < $1.recordedAt }
    }

    private func persistProgressHistory(_ snapshots: [GlowProgressSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: progressHistoryKey)
        progressHistory = snapshots
    }

    private func recordProgressSnapshot() {
        guard viewModel.page != nil else { return }
        let date = Date()
        let dayId = progressSnapshotDayId(date)
        let totalSteps = max(viewModel.morningSteps.count + viewModel.eveningSteps.count, 0)
        let snapshot = GlowProgressSnapshot(
            id: dayId,
            recordedAt: date,
            score: Int((viewModel.skinScore * 100).rounded()),
            completedSteps: viewModel.completedSteps.count,
            totalSteps: totalSteps,
            morningStreak: viewModel.streaks?.morning ?? 0,
            eveningStreak: viewModel.streaks?.evening ?? 0
        )

        var snapshots = progressHistory.sorted { $0.recordedAt < $1.recordedAt }
        if let index = snapshots.firstIndex(where: { $0.id == dayId }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        // Keep last 120 daily points (~4 months) in local storage.
        if snapshots.count > 120 {
            snapshots.removeFirst(snapshots.count - 120)
        }
        persistProgressHistory(snapshots)
    }

    private func progressSnapshotDayId(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func progressDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func progressTimelineSubtitle(_ snapshot: GlowProgressSnapshot) -> String {
        let stepsTotal = max(snapshot.totalSteps, 1)
        let streak = max(snapshot.morningStreak, snapshot.eveningStreak)
        return "Score \(snapshot.score) • \(snapshot.completedSteps)/\(stepsTotal) steps • Streak \(streak)d"
    }

    private func progressMetricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "87878E"))
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: "FAF9FC"))
        .cornerRadius(12)
    }
    
    // MARK: - Formatters
    
    private func formatGoal(_ goal: String) -> String {
        goal.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formattedGoals(_ goals: [String]) -> [String] {
        goals.map { formatGoal($0) }
    }
    
    private func formatConcern(_ concern: String) -> String {
        concern.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formattedConcerns(_ concerns: [String]) -> [String] {
        concerns.map { formatConcern($0) }
    }
    
    private func formatSunscreen(_ usage: String?) -> String {
        switch usage {
        case "always": return "Always"
        case "often": return "Often"
        case "sometimes": return "Sometimes"
        case "rarely": return "Rarely"
        case "never": return "Never"
        default: return usage?.capitalized ?? "—"
        }
    }
    
    private func formatWashFrequency(_ freq: String) -> String {
        switch freq {
        case "daily": return "Daily"
        case "2_3_weekly": return "2-3x / Week"
        case "weekly": return "Weekly"
        case "biweekly": return "Every 2 Weeks"
        default: return freq.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func feedRoutineSteps(for type: HomeView.RoutineType) -> [FeedRoutineStep] {
        let source: [SkinPageRoutineStep]
        switch type {
        case .morning:
            source = viewModel.morningSteps
        case .evening:
            source = viewModel.eveningSteps
        case .weekly:
            source = []
        }

        return source.map { step in
            FeedRoutineStep(
                step: step.step,
                name: step.name,
                tip: step.instructions,
                product_id: step.product_id,
                product_name: step.product_name,
                product_brand: step.product_brand,
                product_price: step.product_price,
                product_image: step.product_image,
                buy_link: nil
            )
        }
    }

    private func shareText(title: String, steps: [SkinPageRoutineStep]) -> String {
        let lines = steps.sorted { $0.step < $1.step }.map { step -> String in
            var line = "\(step.step). \(step.name)"
            if let productName = step.product_name, !productName.isEmpty {
                line += " - \(productName)"
            }
            if let brand = step.product_brand, !brand.isEmpty {
                line += " (\(brand))"
            }
            if let instructions = step.instructions, !instructions.isEmpty {
                line += "\n   \(instructions)"
            }
            return line
        }
        return "\(title)\n\n" + lines.joined(separator: "\n\n")
    }

    private var fullRoutineShareText: String {
        let morning = shareText(title: "Morning Glow", steps: viewModel.morningSteps)
        let evening = shareText(title: "Evening Repair", steps: viewModel.eveningSteps)
        return "\(morning)\n\n\(evening)"
    }

    private var normalizedTypedRoutineKey: String {
        routineKeyInput
            .uppercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private func importRoutineUsingTypedKey() {
        let key = normalizedTypedRoutineKey
        guard key.count >= 6 else {
            libraryStatusIsError = true
            libraryStatusMessage = "Enter a valid routine key."
            return
        }
        guard !isImportingSharedRoutine else { return }
        isImportingSharedRoutine = true
        libraryStatusMessage = nil

        Task {
            do {
                let payload = try await APIService.shared.fetchRoutineByKey(key)
                let stored = storeImportedRoutine(
                    payload: payload,
                    sourceLabel: "Routine Key",
                    sourceToken: nil,
                    routineKey: payload.routine_key ?? key
                )
                guard stored else {
                    throw APIError.serverMessage("That key is valid but has no morning/evening routine.")
                }
                await MainActor.run {
                    routineKeyInput = ""
                    routineLibrary = SessionManager.shared.routineLibrary
                    selectedTab = .routine
                    showAddRoutineModal = false
                    isImportingSharedRoutine = false
                    libraryStatusIsError = false
                    libraryStatusMessage = "Routine key recognized. Saved to your library."
                }
            } catch {
                await MainActor.run {
                    isImportingSharedRoutine = false
                    libraryStatusIsError = true
                    libraryStatusMessage = error.localizedDescription
                }
            }
        }
    }

    @discardableResult
    private func storeImportedRoutine(
        payload: APIService.SharedRoutineFetchResponse,
        sourceLabel: String,
        sourceToken: String?,
        routineKey: String?
    ) -> Bool {
        let morning = payload.routine.morning ?? []
        let evening = payload.routine.evening ?? []
        let weekly = payload.routine.weekly ?? []

        if morning.isEmpty && evening.isEmpty {
            return false
        }

        let title: String
        if let routineKey, !routineKey.isEmpty {
            title = "Routine \(routineKey)"
        } else {
            title = "Imported Routine"
        }

        SessionManager.shared.addRoutineToLibrary(
            title: title,
            morning: morning,
            evening: evening,
            weekly: weekly,
            sourceLabel: sourceLabel,
            sourceToken: sourceToken
        )
        return true
    }

    private func consumePendingSharedRoutineTokenIfNeeded() {
        guard let token = SessionManager.shared.consumePendingSharedRoutineToken(),
              !token.isEmpty else { return }
        importSharedRoutine(token: token)
    }

    private func importSharedRoutine(token: String) {
        guard !token.isEmpty else { return }
        guard !isImportingSharedRoutine else { return }
        isImportingSharedRoutine = true
        libraryStatusMessage = nil

        Task {
            do {
                let payload = try await APIService.shared.fetchSharedRoutine(token: token)
                let morning = payload.routine.morning ?? []
                let evening = payload.routine.evening ?? []
                if morning.isEmpty && evening.isEmpty {
                    throw APIError.serverMessage("Shared routine has no morning/evening steps.")
                }

                storeImportedRoutine(
                    payload: payload,
                    sourceLabel: "Shared Link",
                    sourceToken: token,
                    routineKey: payload.routine_key
                )

                await MainActor.run {
                    routineLibrary = SessionManager.shared.routineLibrary
                    selectedTab = .routine
                    isImportingSharedRoutine = false
                    libraryStatusIsError = false
                    libraryStatusMessage = "Routine imported. Apply it from your library."
                }
            } catch {
                await MainActor.run {
                    isImportingSharedRoutine = false
                    libraryStatusIsError = true
                    libraryStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyRoutineLibraryItem(_ item: SessionManager.RoutineLibraryItem) {
        guard let userId = SessionManager.shared.userId, !userId.isEmpty else {
            libraryStatusIsError = true
            libraryStatusMessage = "Sign in to apply shared routines."
            return
        }
        guard !isApplyingLibraryRoutine else { return }
        isApplyingLibraryRoutine = true
        libraryStatusMessage = nil

        Task {
            do {
                let morning = item.morning.enumerated().map { index, step in
                    APIService.RoutineUpdateStep(
                        step: index + 1,
                        name: step.name,
                        instructions: step.tip ?? "",
                        frequency: "daily",
                        product_id: step.product_id,
                        product_name: step.product_name
                    )
                }
                let evening = item.evening.enumerated().map { index, step in
                    APIService.RoutineUpdateStep(
                        step: index + 1,
                        name: step.name,
                        instructions: step.tip ?? "",
                        frequency: "daily",
                        product_id: step.product_id,
                        product_name: step.product_name
                    )
                }

                try await APIService.shared.updateRoutine(
                    userId: userId,
                    morning: morning,
                    evening: evening,
                    weekly: [],
                    summary: "Routine applied from library"
                )

                await MainActor.run {
                    isApplyingLibraryRoutine = false
                    libraryStatusIsError = false
                    libraryStatusMessage = "Routine applied to your main Morning + Evening plan."
                    viewModel.load(userId: userId, forceRefresh: true)
                }
            } catch {
                await MainActor.run {
                    isApplyingLibraryRoutine = false
                    libraryStatusIsError = true
                    libraryStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func prepareRoutineShare(routineType: String?, fallbackTitle: String, fallbackSteps: [SkinPageRoutineStep]) {
        guard let userId = SessionManager.shared.userId else { return }
        isPreparingShare = true
        shareError = nil

        Task {
            do {
                let response = try await APIService.shared.createRoutineShareLink(userId: userId, routineType: routineType)
                let routineKey = response.routine_key?.trimmingCharacters(in: .whitespacesAndNewlines)
                let keyLine: String = {
                    if let key = routineKey, !key.isEmpty {
                        return "\n\nRoutine Key: \(key)"
                    }
                    return ""
                }()
                let fallbackText = shareText(title: fallbackTitle, steps: fallbackSteps) + keyLine
                let shareUrl = URL(string: response.share_url)
                let entries = fallbackSteps
                    .sorted { $0.step < $1.step }
                    .map { step in
                        RoutineShareCardEntry(
                            stepNumber: step.step,
                            stepName: step.name,
                            productName: step.product_name,
                            productBrand: step.product_brand
                        )
                    }
                await MainActor.run {
                    let subtitle = routineKey.map { "Key \($0) • Share to TikTok and Instagram." } ?? "Share to TikTok, Instagram, and messages."
                    let cardImage = renderRoutineShareCardImage(
                        title: fallbackTitle,
                        subtitle: subtitle,
                        entries: Array(entries.prefix(7)),
                        routineKey: routineKey
                    )
                    let items = makeRoutineShareItems(
                        cardImage: cardImage,
                        shareURL: shareUrl,
                        fallbackText: fallbackText
                    )
                    sharePreview = RoutineSharePreviewData(
                        title: fallbackTitle,
                        subtitle: subtitle,
                        routineKey: routineKey,
                        entries: entries,
                        cardImage: cardImage,
                        shareItems: items
                    )
                    isPreparingShare = false
                }
            } catch {
                await MainActor.run {
                    isPreparingShare = false
                    shareError = "Couldn't prepare share link right now."
                }
            }
        }
    }
}

// MARK: - Routine Step Row
struct SkinRoutineStepRow: View {
    let step: SkinPageRoutineStep
    let isCompleted: Bool
    let accentColor: Color
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Check Circle
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(isCompleted ? accentColor : Color(hex: "D4D4DB"), lineWidth: 2)
                        .frame(width: 28, height: 28)
                    
                    if isCompleted {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Step Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text("Step \(step.step)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accentColor.opacity(0.95))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.12))
                        .cornerRadius(8)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "CCCCCC"))
                    
                    Text(step.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isCompleted ? Color(hex: "A2A2A9") : Color(hex: "252529"))
                        .strikethrough(isCompleted)
                }
                
                // Product Info
                if let productName = step.product_name, !productName.isEmpty {
                    HStack(spacing: 5) {
                        if let brand = step.product_brand, !brand.isEmpty {
                            Text(brand)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "FF5C95"))
                        }
                        Text(productName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "6D6D73"))
                            .lineLimit(1)
                        
                        if let price = step.product_price, price > 0 {
                            Text("$\(price.roundedUpPrice)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: "8B8B92"))
                        }
                    }

                }
                
                // Instructions
                if let instructions = step.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "A0A0A8"))
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Product Image Thumbnail
            if let imgUrl = step.product_image, let url = URL(string: imgUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .cornerRadius(8)
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "F5F5F5"))
                            .frame(width: 36, height: 36)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color(hex: "FBFAFD"))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "EFEAF0"), lineWidth: 1)
        )
        .opacity(isCompleted ? 0.7 : 1.0)
    }
}

// MARK: - Timeline Row
struct TimelineRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isLast: Bool
    let accessory: AnyView?
    
    init(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isLast: Bool,
        accessory: AnyView? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.isLast = isLast
        self.accessory = accessory
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)
                }
                
                if !isLast {
                    Rectangle()
                        .fill(Color(hex: "F0D9E3"))
                        .frame(width: 2, height: 28)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "888888"))
                    .lineSpacing(3)
            }
            
            Spacer()
            
            if let accessory {
                accessory
            }
        }
    }
}

struct ProgressTrendBars: View {
    let snapshots: [GlowProgressSnapshot]

    private var minScore: Double {
        Double(snapshots.map(\.score).min() ?? 0)
    }

    private var maxScore: Double {
        Double(snapshots.map(\.score).max() ?? 100)
    }

    private func normalizedHeight(for score: Int) -> CGFloat {
        let minH: CGFloat = 20
        let maxH: CGFloat = 96
        let spread = max(maxScore - minScore, 1)
        let progress = (Double(score) - minScore) / spread
        return minH + (maxH - minH) * CGFloat(progress)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(snapshots) { snapshot in
                VStack(spacing: 6) {
                    Text("\(snapshot.score)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "66666D"))

                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FF6B9D"), Color(hex: "FFB4C8")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 20, height: normalizedHeight(for: snapshot.score))

                    Text(shortDate(snapshot.recordedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "9A9AA1"))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views
struct QuickStat: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "29292D"))
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "8A8A92"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(hex: "F9F8FB"))
        .cornerRadius(13)
    }
}

struct FlowLayoutView<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content
    
    private var rows: [[Data.Element]] {
        createRows()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(rows[rowIndex], id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }
    
    private func createRows() -> [[Data.Element]] {
        var rows: [[Data.Element]] = [[]]
        var currentRow = 0
        var currentWidth: CGFloat = 0
        let maxWidth: CGFloat = UIScreen.main.bounds.width - 80
        
        for item in items {
            let itemWidth: CGFloat = 120
            
            if currentWidth + itemWidth > maxWidth {
                currentRow += 1
                rows.append([])
                currentWidth = 0
            }
            
            rows[currentRow].append(item)
            currentWidth += itemWidth
        }
        
        return rows
    }
}

#Preview {
    SkinView()
}
