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
    @State private var isPreparingShare = false
    @State private var shareError: String?
    
    enum SkinTab: String, CaseIterable {
        case routine = "My Routine"
        case profile = "Profile"
        case progress = "Progress"
    }
    
    var body: some View {
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
                    switch selectedTab {
                    case .routine:
                        routineContent
                    case .profile:
                        profileContent
                    case .progress:
                        progressContent
                    }
                } else if viewModel.error != nil {
                    errorState
                }
                
                Spacer().frame(height: 120)
            }
            .padding(.top, 16)
        }
        .background(PinkDrapeBackground().ignoresSafeArea())
        .refreshable {
            viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
        }
        .onAppear {
            if viewModel.page == nil {
                viewModel.load(userId: SessionManager.shared.userId)
            }
        }
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
                completedSteps: Binding(
                    get: { viewModel.completedSteps },
                    set: { viewModel.completedSteps = $0 }
                ),
                streaks: $routineStreaks,
                userId: SessionManager.shared.userId ?? "",
                onRoutineUpdated: {
                    viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(items: shareItems)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GlowUpNotificationDestination"))) { note in
            guard let destination = note.userInfo?["destination"] as? String else { return }
            if destination == "routine" {
                selectedTab = .routine
            } else if destination == "progress" {
                selectedTab = .progress
            }
        }
        .onChange(of: viewModel.page?.streaks.morning ?? 0) { _, newVal in
            routineStreaks.morning = newVal
        }
        .onChange(of: viewModel.page?.streaks.evening ?? 0) { _, newVal in
            routineStreaks.evening = newVal
        }
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.agent?.page_title ?? "Your Glow")
                    .font(.custom("Didot", size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Text(viewModel.agent?.page_subtitle ?? "Personalized care for your skin")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "888888"))
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: {
                viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "FF6B9D"))
                    .padding(10)
                    .background(Color(hex: "FFE4EC"))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Score Card
    private var scoreCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Score Ring
                ZStack {
                    Circle()
                        .stroke(Color(hex: "FFE4EC"), lineWidth: 7)
                        .frame(width: 90, height: 90)
                    
                    Circle()
                        .trim(from: 0, to: viewModel.skinScore)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "FF6B9D"), Color(hex: "FFB4C8")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8), value: viewModel.skinScore)
                    
                    VStack(spacing: 1) {
                        Text("\(Int(viewModel.skinScore * 100))")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        Text("Score")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "999999"))
                    }
                }
                
                // Profile Quick Info
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "FF6B9D"))
                        Text("Skin Type")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "999999"))
                    }
                    Text(viewModel.profile?.skin_type.capitalized ?? "Normal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "FF6B9D"))
                        Text("Focus")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "999999"))
                    }
                    Text(viewModel.agent?.weekly_focus ?? "Consistency")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "FF6B9D"))
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            // Quick Stats Row
            HStack(spacing: 10) {
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
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Tab Picker
    private var tabPicker: some View {
        HStack(spacing: 6) {
            ForEach(SkinTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : Color(hex: "666666"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    LinearGradient(
                                        colors: [Color(hex: "FF6B9D"), Color(hex: "FFB4C8")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                } else {
                                    LinearGradient(colors: [Color.white, Color.white], startPoint: .leading, endPoint: .trailing)
                                }
                            }
                        )
                        .cornerRadius(12)
                        .shadow(
                            color: selectedTab == tab ? Color(hex: "FF6B9D").opacity(0.25) : .clear,
                            radius: 6, x: 0, y: 3
                        )
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Routine Content
    private var routineContent: some View {
        VStack(spacing: 16) {
            if !viewModel.morningSteps.isEmpty || !viewModel.eveningSteps.isEmpty {
                HStack {
                    Text("Routine Actions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "777777"))
                    
                    Spacer()
                    
                    Button(action: { prepareRoutineShare(routineType: nil, fallbackTitle: "My Routine", fallbackSteps: viewModel.morningSteps + viewModel.eveningSteps) }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isPreparingShare ? Color(hex: "AAAAAA") : Color(hex: "666666"))
                    }
                    .disabled(isPreparingShare)
                    
                    Menu {
                        if !viewModel.morningSteps.isEmpty {
                            Button("Edit Morning") { routineEditorType = .morning }
                        }
                        if !viewModel.eveningSteps.isEmpty {
                            Button("Edit Evening") { routineEditorType = .evening }
                        }
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                    }
                }

                if let shareError {
                    Text(shareError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "D64545"))
                }
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
                    Text("Complete onboarding to get your personalized routine with product recommendations")
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
    
    private func routineSection(title: String, icon: String, color: Color, steps: [SkinPageRoutineStep], routineType: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Spacer()
                
                // Completion count
                let doneCount = steps.filter { viewModel.completedSteps.contains(viewModel.stepKey($0, routineType: routineType)) }.count
                Text("\(doneCount)/\(steps.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(doneCount == steps.count ? Color(hex: "4ECDC4") : Color(hex: "999999"))

                Button(action: { prepareRoutineShare(routineType: routineType, fallbackTitle: title, fallbackSteps: steps) }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isPreparingShare ? Color(hex: "B5B5B5") : Color(hex: "777777"))
                        .padding(6)
                        .background(Color(hex: "F6F6F6"))
                        .clipShape(Circle())
                }
                .disabled(isPreparingShare)

                Button(action: {
                    routineEditorType = routineType == "morning" ? .morning : .evening
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                        .padding(6)
                        .background(Color(hex: "FFE8F0"))
                        .clipShape(Circle())
                }
            }
            
            // Steps
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
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Profile Content
    private var profileContent: some View {
        VStack(spacing: 14) {
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
            if let goals = viewModel.profile?.skin_goals, !goals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Goals")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    FlowLayoutView(items: goals.map { formatGoal($0) }) { goal in
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
            if let concerns = viewModel.profile?.skin_concerns, !concerns.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Concerns")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    FlowLayoutView(items: concerns.map { formatConcern($0) }) { concern in
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
                    
                    if let hairConcerns = viewModel.profile?.hair_concerns, !hairConcerns.isEmpty {
                        FlowLayoutView(items: hairConcerns.map { formatConcern($0) }) { concern in
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
        let totalSteps = viewModel.morningSteps.count + viewModel.eveningSteps.count
        let completed = viewModel.completedSteps.count
        let morningStreak = viewModel.streaks?.morning ?? 0
        let eveningStreak = viewModel.streaks?.evening ?? 0
        
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Timeline")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                TimelineRow(
                    title: "Today",
                    subtitle: totalSteps > 0
                        ? "\(completed)/\(totalSteps) routine steps completed"
                        : "No routine steps yet — complete onboarding to start",
                    icon: "checkmark.circle.fill",
                    color: Color(hex: "4ECDC4"),
                    isLast: false
                )
                
                TimelineRow(
                    title: "Streaks",
                    subtitle: "Morning \(morningStreak)d · Evening \(eveningStreak)d",
                    icon: "flame.fill",
                    color: Color(hex: "FF6B6B"),
                    isLast: false
                )
                
                if let note = viewModel.agent?.progress_note, !note.isEmpty {
                    TimelineRow(
                        title: "Coach Note",
                        subtitle: note,
                        icon: "quote.opening",
                        color: Color(hex: "FFB4C8"),
                        isLast: false
                    )
                }
                
                TimelineRow(
                    title: "Next photo check-in",
                    subtitle: "Biweekly progress photo",
                    icon: "camera.fill",
                    color: Color(hex: "FF6B9D"),
                    isLast: true,
                    accessory: AnyView(
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "camera")
                                Text("Take Photo")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "FF6B9D"), Color(hex: "FFB4C8")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                        }
                    )
                )
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(16)
            
            // Advanced Analysis (Premium)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Advanced Analysis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    Spacer()
                    if !SessionManager.shared.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "FF6B9D"))
                    }
                }
                
                if SessionManager.shared.isPremium {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "9B6BFF").opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color(hex: "9B6BFF"))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Skin improvement trajectory")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "666666"))
                                Text("+12% Clarity")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(hex: "2D2D2D"))
                            }
                        }
                        
                        Text("Your consistent use of Vitamin C is showing results in brightness metrics based on your last 3 photos.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "555555"))
                            .lineSpacing(4)
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color(hex: "F8F6FF"))
                    .cornerRadius(12)
                } else {
                    Button(action: { showPaywall = true }) {
                        VStack(spacing: 16) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 32))
                                .foregroundColor(Color(hex: "FF6B9D"))
                                .padding(.top, 8)
                            
                            VStack(spacing: 6) {
                                Text("Unlock AI Progress Tracking")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color(hex: "2D2D2D"))
                                
                                Text("See exactly which products are working\nand track your glow-up with computer vision.")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "888888"))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                            }
                            
                            Text("UPGRADE TO GLOWUP+")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(hex: "FF6B9D"))
                                .cornerRadius(20)
                                .shadow(color: Color(hex: "FF6B9D").opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .foregroundColor(Color(hex: "FFB4C8").opacity(0.6))
                                .background(Color(hex: "FFF5F8").cornerRadius(16))
                        )
                    }
                }
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(16)
        }

        .padding(.horizontal, 20)
    }
    
    // MARK: - Formatters
    
    private func formatGoal(_ goal: String) -> String {
        goal.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    private func formatConcern(_ concern: String) -> String {
        concern.replacingOccurrences(of: "_", with: " ").capitalized
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
            if let productId = step.product_id, !productId.isEmpty {
                line += "\n   Product ID: \(productId)"
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

    private func prepareRoutineShare(routineType: String?, fallbackTitle: String, fallbackSteps: [SkinPageRoutineStep]) {
        guard let userId = SessionManager.shared.userId else { return }
        isPreparingShare = true
        shareError = nil

        Task {
            do {
                let response = try await APIService.shared.createRoutineShareLink(userId: userId, routineType: routineType)
                let fallbackText = shareText(title: fallbackTitle, steps: fallbackSteps)
                let shareUrl = URL(string: response.share_url)
                await MainActor.run {
                    var items: [Any] = [fallbackText]
                    if let shareUrl { items.insert(shareUrl, at: 0) }
                    shareItems = items
                    isPreparingShare = false
                    showShareSheet = true
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
                        .stroke(isCompleted ? accentColor : Color(hex: "DDDDDD"), lineWidth: 2)
                        .frame(width: 26, height: 26)
                    
                    if isCompleted {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 26, height: 26)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            
            // Step Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Step \(step.step)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.8))
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "CCCCCC"))
                    
                    Text(step.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isCompleted ? Color(hex: "AAAAAA") : Color(hex: "2D2D2D"))
                        .strikethrough(isCompleted)
                }
                
                // Product Info
                if let productName = step.product_name, !productName.isEmpty {
                    HStack(spacing: 4) {
                        if let brand = step.product_brand, !brand.isEmpty {
                            Text(brand)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "FF6B9D"))
                        }
                        Text(productName)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "777777"))
                            .lineLimit(1)
                        
                        if let price = step.product_price, price > 0 {
                            Text("$\(price.roundedUpPrice)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "999999"))
                        }
                    }

                    if let productId = step.product_id, !productId.isEmpty {
                        Text("ID \(productId)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(hex: "A0A0A0"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                // Instructions
                if let instructions = step.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "AAAAAA"))
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
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
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

// MARK: - Supporting Views
struct QuickStat: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "2D2D2D"))
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "888888"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(hex: "FAFAFA"))
        .cornerRadius(12)
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
