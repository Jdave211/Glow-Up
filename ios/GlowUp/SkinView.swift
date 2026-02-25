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
    var weeklySteps: [SkinPageRoutineStep] { routine?.weekly ?? [] }
    
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
    private struct ProgressGalleryEntry: Identifiable {
        let id: String
        let imageName: String
        let date: String
        let label: String
        let score: Int
    }

    @StateObject private var viewModel = SkinPageViewModel()
    @State private var selectedTab: SkinTab = .progress
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
    @State private var selectedTimelinePhoto: ProgressGalleryEntry?
    
    enum SkinTab: String, CaseIterable {
        case progress = "Progress"
        case routine = "My Routine"
    }
    
    private var skinToneBackgroundImageName: String {
        guard let value = viewModel.profile?.skin_tone_value else { return "lightskin_black" }
        if value < 0.35 { return "white" }
        if value < 0.70 { return "lightskin_black" }
        return "black"
    }

    var body: some View {
        AnyView(observedSkinScreen)
    }

    private var baseSkinScreen: AnyView {
        AnyView(
            skinRootContent
                .background(skinBackgroundLayer)
                .refreshable {
                    viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
                }
                .onAppear(perform: handleOnAppear)
        )
    }

    private var sheetedSkinScreen: AnyView {
        AnyView(
            baseSkinScreen
                .sheet(isPresented: $showPaywall) {
                    PremiumPaywallView()
                }
                .sheet(item: $routineEditorType) { routineType in
                    routineEditorSheet(for: routineType)
                }
                .sheet(isPresented: $showAddRoutineModal) {
                    addRoutineModalContent
                }
                .sheet(isPresented: $showShareSheet) {
                    ActivityShareSheet(items: shareItems)
                }
                .overlay(sharePreviewOverlay)
                .overlay(timelinePhotoOverlay)
        )
    }

    private var observedSkinScreen: AnyView {
        let destinationObserved = attachDestinationObserver(to: sheetedSkinScreen)
        let importObserved = attachRoutineImportObserver(to: destinationObserved)
        let routineObserved = attachRoutineUpdateObserver(to: importObserved)
        let morningObserved = attachMorningStreakObserver(to: routineObserved)
        let eveningObserved = attachEveningStreakObserver(to: morningObserved)
        let completedObserved = attachCompletedStepsObserver(to: eveningObserved)
        return attachSkinScoreObserver(to: completedObserved)
    }

    private var morningStreakValue: Int {
        viewModel.page?.streaks.morning ?? 0
    }

    private var eveningStreakValue: Int {
        viewModel.page?.streaks.evening ?? 0
    }

    private var completedStepsCount: Int {
        viewModel.completedSteps.count
    }

    private var skinScoreRawValue: Double {
        viewModel.page?.insights.skin_score ?? -1
    }

    private func attachDestinationObserver(to view: AnyView) -> AnyView {
        AnyView(
            view.onReceive(NotificationCenter.default.publisher(for: .glowUpNotificationDestination)) { note in
                handleDestinationNotification(note)
            }
        )
    }

    private func attachRoutineImportObserver(to view: AnyView) -> AnyView {
        AnyView(
            view.onReceive(NotificationCenter.default.publisher(for: .glowUpOpenRoutineImport)) { note in
                handleRoutineImportNotification(note)
            }
        )
    }

    private func attachRoutineUpdateObserver(to view: AnyView) -> AnyView {
        AnyView(
            view.onReceive(NotificationCenter.default.publisher(for: .glowUpRoutineDidUpdate)) { _ in
                viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
            }
        )
    }

    private func attachMorningStreakObserver(to view: AnyView) -> AnyView {
        AnyView(
            view.onChange(of: morningStreakValue) { _, newVal in
                handleMorningStreakChange(newVal)
            }
        )
    }

    private func attachEveningStreakObserver(to view: AnyView) -> AnyView {
        AnyView(
            view.onChange(of: eveningStreakValue) { _, newVal in
                handleEveningStreakChange(newVal)
            }
        )
    }

    private func attachCompletedStepsObserver(to view: AnyView) -> AnyView {
        AnyView(
            view.onChange(of: completedStepsCount) { _, _ in
                recordProgressSnapshot()
            }
        )
    }

    private func attachSkinScoreObserver(to view: AnyView) -> AnyView {
        AnyView(
            view.onChange(of: skinScoreRawValue) { _, _ in
                recordProgressSnapshot()
            }
        )
    }

    private func routineEditorSheet(for routineType: HomeView.RoutineType) -> some View {
        RoutineDetailSheet(
            routineType: routineType,
            steps: feedRoutineSteps(for: routineType),
            morningSteps: feedRoutineSteps(for: .morning),
            eveningSteps: feedRoutineSteps(for: .evening),
            weeklySteps: feedRoutineSteps(for: .weekly),
            completedSteps: completedStepsBinding,
            streaks: $routineStreaks,
            userId: SessionManager.shared.userId ?? "",
            onRoutineUpdated: {
                viewModel.load(userId: SessionManager.shared.userId, forceRefresh: true)
            }
        )
    }

    private var skinBackgroundLayer: some View {
        ZStack(alignment: .top) {
            PinkDrapeBackground().ignoresSafeArea()

            if viewModel.page != nil {
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
    }

    @ViewBuilder
    private var sharePreviewOverlay: some View {
        if let sharePreview {
            RoutineSharePreviewModal(
                preview: sharePreview,
                onClose: { self.sharePreview = nil },
                onShare: { handleSharePreviewShare(sharePreview) }
            )
            .zIndex(2)
        }
    }

    @ViewBuilder
    private var timelinePhotoOverlay: some View {
        if let selectedTimelinePhoto {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.selectedTimelinePhoto = nil
                        }
                    }

                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.selectedTimelinePhoto = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(hex: "666666"))
                                .padding(10)
                                .background(Color.white.opacity(0.9))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Image(selectedTimelinePhoto.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Text(selectedTimelinePhoto.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "454545"))
                        Text("•")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "9A9A9A"))
                        Text(selectedTimelinePhoto.date)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "8A8A92"))
                        Spacer()
                        Text("Score \(selectedTimelinePhoto.score)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "FF5C95"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "FFF0F5"))
                            .cornerRadius(10)
                    }
                }
                .padding(16)
                .background(Color(hex: "FCFBFD").opacity(0.95))
                .cornerRadius(20)
                .padding(.horizontal, 20)
                .shadow(color: Color.black.opacity(0.16), radius: 26, x: 0, y: 12)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .zIndex(3)
        }
    }

    private var skinRootContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                screenStateContent
                
                Spacer().frame(height: 120)
            }
            .padding(.top, 16)
        }
    }

    private var screenStateContent: AnyView {
        if viewModel.isLoading && viewModel.page == nil {
            return AnyView(loadingState)
        }

        if viewModel.page != nil {
            return AnyView(
                Group {
                    headerSection
                    tabPicker
                    selectedTabContent
                }
            )
        }

        if viewModel.error != nil {
            return AnyView(errorState)
        }

        return AnyView(EmptyView())
    }

    private var selectedTabContent: AnyView {
        switch selectedTab {
        case .progress:
            return AnyView(progressContent)
        case .routine:
            return AnyView(routineContent)
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Skin Health")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "FF5C95"))
                    .textCase(.uppercase)
                    .tracking(1)
                
                Text("Glow Score: 92")
                    .font(.custom("Didot", size: 36))
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                HStack(spacing: 8) {
                    Text(viewModel.profile?.skin_type.capitalized ?? "Normal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "666666"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(8)
                    
                    Text("Focus: \(viewModel.agent?.weekly_focus ?? "Consistency")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "8A8A92"))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Simple Score Visual
            ZStack {
                Circle()
                    .stroke(Color(hex: "FFF0F5"), lineWidth: 6)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.92)
                    .stroke(
                        LinearGradient(colors: [Color(hex: "FF5C95"), Color(hex: "FF98B7")], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                Text("92")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
            }
        }
        .padding(24)
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
        let isEvening = routineType == "evening"
        let isMorning = routineType == "morning"
        
        let textColor = isEvening ? Color.white : Color(hex: "2D2D2D")
        let completionTint = doneCount == steps.count ? Color(hex: "3B8F68") : (isEvening ? Color.white.opacity(0.5) : Color(hex: "8E8E95"))
        let rowBg = isEvening ? Color(hex: "2C2C35").opacity(0.6) : Color(hex: "FBFAFD")
        
        return VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isEvening ? Color.white.opacity(0.2) : color.opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isEvening ? .white : color)
                }
                
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(textColor)
                
                Spacer()
                
                Text("\(doneCount)/\(steps.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isEvening ? .white : completionTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isEvening ? Color.white.opacity(0.2) : Color(hex: "F5F5F7"))
                    .cornerRadius(8)

                Button(action: { prepareRoutineShare(routineType: routineType, fallbackTitle: title, fallbackSteps: steps) }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isPreparingShare ? (isEvening ? Color.white.opacity(0.3) : Color(hex: "B5B5B5")) : (isEvening ? Color.white.opacity(0.8) : Color(hex: "6D6D73")))
                        .padding(7)
                        .background(isEvening ? Color.white.opacity(0.1) : Color(hex: "F3F3F6"))
                        .clipShape(Circle())
                }
                .disabled(isPreparingShare)

                Button(action: {
                    routineEditorType = routineType == "morning" ? .morning : .evening
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isEvening ? .white : Color(hex: "FF5C95"))
                        .padding(7)
                        .background(isEvening ? Color(hex: "FF5C95").opacity(0.8) : Color(hex: "FFEAF2"))
                        .clipShape(Circle())
                }
            }
            
            // Steps
            VStack(spacing: 10) {
                ForEach(steps) { step in
                    SkinRoutineStepRow(
                        step: step,
                        isCompleted: viewModel.completedSteps.contains(viewModel.stepKey(step, routineType: routineType)),
                        accentColor: isEvening ? Color(hex: "A088FF") : color,
                        onToggle: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            viewModel.toggleStep(step, routineType: routineType)
                        },
                        customTextColor: textColor,
                        customBackgroundColor: rowBg
                    )
                }
            }
        }
        .padding(16)
        .background(
            Group {
                if isEvening {
                    StarryBackground()
                } else if isMorning {
                    LinearGradient(
                        colors: [Color(hex: "FFF9E6"), Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.white.opacity(0.94)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isEvening ? Color.white.opacity(0.1) : Color.white.opacity(0.95), lineWidth: 1)
        )
        .cornerRadius(18)
        .shadow(color: isEvening ? Color.black.opacity(0.3) : Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
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
    
    // MARK: - Progress Content
    private struct ProgressSummary {
        let history: [GlowProgressSnapshot]
        let recent: [GlowProgressSnapshot]
        let timeline: [GlowProgressSnapshot]
        let scoreDelta: Int
        let averageCompletion: Double
        let bestStreak: Int

        var hasHistory: Bool { !history.isEmpty }
    }

    private var progressSummary: ProgressSummary {
        let sortedHistory = progressHistory.sorted { $0.recordedAt < $1.recordedAt }
        let recent = Array(sortedHistory.suffix(8))
        let timeline = recent
        let scoreDelta = (sortedHistory.last?.score ?? 0) - (sortedHistory.first?.score ?? 0)
        let averageCompletion = sortedHistory.isEmpty
            ? 0
            : sortedHistory.map(\.completionRate).reduce(0, +) / Double(sortedHistory.count)
        let bestStreak = sortedHistory.map { max($0.morningStreak, $0.eveningStreak) }.max() ?? 0
        return ProgressSummary(
            history: sortedHistory,
            recent: recent,
            timeline: timeline,
            scoreDelta: scoreDelta,
            averageCompletion: averageCompletion,
            bestStreak: bestStreak
        )
    }

    private var progressContent: some View {
        let summary = progressSummary
        return VStack(spacing: 24) {
            progressGallerySection(summary)
            progressComparisonSection(summary)
            progressOverviewCard(summary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - New Visual Progress Helpers
    @ViewBuilder
    private func progressGallerySection(_ summary: ProgressSummary) -> some View {
        let entries = progressGalleryEntries(from: summary)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Glow Up Journey")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "2D2D2D"))
                Text("Your skin's evolution over time")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "8A8A92"))
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTimelinePhoto = entry
                            }
                        } label: {
                            TimelinePhotoItem(
                                imageName: entry.imageName,
                                date: entry.date,
                                label: entry.label,
                                score: entry.score
                            )
                        }
                        .buttonStyle(.plain)

                        if index < entries.count - 1 {
                            TimelineConnector()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 15)
            }
        }
    }

    private func progressComparisonSection(_ summary: ProgressSummary) -> some View {
        let beforeLabel = "Before • Jan 24"
        let afterLabel = "After • Feb 23"
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Before & After")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Spacer()
                
                Text("Slide to compare")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "FF5C95"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "FFF0F5"))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 4)
            
            BeforeAfterSlider(
                beforeImage: Image("progress_stage_1"),
                afterImage: Image("progress_stage_3"),
                beforeLabel: beforeLabel,
                afterLabel: afterLabel
            )
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: Color(hex: "FFB4C8").opacity(0.3), radius: 15, x: 0, y: 10)
            .padding(.horizontal, 4)
        }
    }

    private func progressGallerySnapshots(from summary: ProgressSummary) -> [GlowProgressSnapshot] {
        let timeline = summary.timeline
        guard !timeline.isEmpty else { return [] }
        guard timeline.count > 3 else { return timeline }

        let first = timeline.first!
        let middle = timeline[timeline.count / 2]
        let last = timeline.last!

        var selected: [GlowProgressSnapshot] = []
        for snapshot in [first, middle, last] {
            if !selected.contains(where: { $0.id == snapshot.id }) {
                selected.append(snapshot)
            }
        }
        return selected
    }

    private func progressGalleryEntries(from summary: ProgressSummary) -> [ProgressGalleryEntry] {
        // Always use the 3-stage demo so the timeline shows three distinct images (before/mid/after).
        return [
            ProgressGalleryEntry(id: "default-1", imageName: "progress_stage_1", date: "Jan 24", label: "Day 1", score: 59),
            ProgressGalleryEntry(id: "default-2", imageName: "progress_stage_2", date: "Feb 07", label: "Day 14", score: 75),
            ProgressGalleryEntry(id: "default-3", imageName: "progress_stage_3", date: "Feb 23", label: "Day 30", score: 92)
        ]
    }

    private func progressDayLabel(_ snapshot: GlowProgressSnapshot, baselineDate: Date?) -> String {
        guard let baselineDate else { return "Day 1" }
        let days = (Calendar.current.dateComponents([.day], from: baselineDate, to: snapshot.recordedAt).day ?? 0) + 1
        return "Day \(max(days, 1))"
    }

    private func progressOverviewCard(_ summary: ProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Consistency Metrics")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "2D2D2D"))
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                progressMetricCard(
                    title: "Score Change",
                    value: "+33",
                    tint: Color(hex: "3B8F68")
                )
                progressMetricCard(
                    title: "Avg Consistency",
                    value: "98%",
                    tint: Color(hex: "5B86FF")
                )
                progressMetricCard(
                    title: "Best Streak",
                    value: "14d",
                    tint: Color(hex: "FF8E3C")
                )
            }
        }
    }

    @ViewBuilder
    private func progressTrendCard(_ summary: ProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score Trend")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(hex: "666666"))
            
            if summary.hasHistory {
                ProgressTrendBars(snapshots: summary.recent)
                    .padding(.top, 10)
            } else {
                Text("No data yet. Complete routines to see your trend.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "8F8F96"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.8))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func progressTimelineCard(_ summary: ProgressSummary) -> some View {
        let entries = progressTimelineEntries(from: summary)
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "2D2D2D"))

            if summary.hasHistory && !entries.isEmpty {
                ZigZagProgressTimeline(entries: entries)
            } else {
                Text("Your timeline will populate as you keep using your routine.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "8F8F96"))
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(16)
    }

    private func progressTimelineEntries(from summary: ProgressSummary) -> [ZigZagProgressTimeline.Entry] {
        summary.timeline.map { snapshot in
            ZigZagProgressTimeline.Entry(
                id: snapshot.id,
                dateText: progressDateLabel(snapshot.recordedAt),
                subtitle: progressTimelineSubtitle(snapshot),
                imageName: progressStageImageName(for: snapshot.score),
                score: snapshot.score
            )
        }
    }

    private func progressStageImageName(for score: Int) -> String {
        if score >= 78 { return "progress_stage_3" }
        if score >= 62 { return "progress_stage_2" }
        return "progress_stage_1"
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
    
    private func feedRoutineSteps(for type: HomeView.RoutineType) -> [FeedRoutineStep] {
        let source: [SkinPageRoutineStep]
        switch type {
        case .morning:
            source = viewModel.morningSteps
        case .evening:
            source = viewModel.eveningSteps
        case .weekly:
            source = viewModel.weeklySteps
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
    var customTextColor: Color? = nil
    var customBackgroundColor: Color? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Check Circle
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(isCompleted ? accentColor : (customTextColor?.opacity(0.5) ?? Color(hex: "D4D4DB")), lineWidth: 2)
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
                        .foregroundColor(customTextColor?.opacity(0.5) ?? Color(hex: "CCCCCC"))
                    
                    Text(step.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isCompleted ? (customTextColor?.opacity(0.6) ?? Color(hex: "A2A2A9")) : (customTextColor ?? Color(hex: "252529")))
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
                            .foregroundColor(customTextColor?.opacity(0.8) ?? Color(hex: "6D6D73"))
                            .lineLimit(1)
                        
                        if let price = step.product_price, price > 0 {
                            Text("$\(price.roundedUpPrice)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(customTextColor?.opacity(0.7) ?? Color(hex: "8B8B92"))
                        }
                    }

                }
                
                // Instructions
                if let instructions = step.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(customTextColor?.opacity(0.6) ?? Color(hex: "A0A0A8"))
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
                            .fill(customBackgroundColor?.opacity(0.5) ?? Color(hex: "F5F5F5"))
                            .frame(width: 36, height: 36)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(customBackgroundColor ?? Color(hex: "FBFAFD"))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(customTextColor?.opacity(0.1) ?? Color(hex: "EFEAF0"), lineWidth: 1)
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

struct ZigZagProgressTimeline: View {
    struct Entry: Identifiable {
        let id: String
        let dateText: String
        let subtitle: String
        let imageName: String
        let score: Int
    }

    let entries: [Entry]

    private let nodeSize: CGFloat = 16
    private let rowSpacing: CGFloat = 108
    private let topInset: CGFloat = 18

    private var totalHeight: CGFloat {
        (topInset * 2) + (CGFloat(max(entries.count - 1, 0)) * rowSpacing)
    }

    var body: some View {
        GeometryReader { proxy in
            let leftX: CGFloat = 28
            let rightX = max(leftX + 120, proxy.size.width - 28)
            let cardWidth = min(max(proxy.size.width * 0.62, 190), proxy.size.width - 96)
            let leftCardX = min(proxy.size.width - (cardWidth / 2) - 8, leftX + (cardWidth / 2) + 28)
            let rightCardX = max((cardWidth / 2) + 8, rightX - (cardWidth / 2) - 28)

            ZStack(alignment: .topLeading) {
                zigZagPath(leftX: leftX, rightX: rightX)

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let isLeft = index.isMultiple(of: 2)
                    let nodeX = isLeft ? leftX : rightX
                    let cardX = isLeft ? leftCardX : rightCardX
                    let pointY = topInset + (CGFloat(index) * rowSpacing)

                    timelineNode
                        .position(x: nodeX, y: pointY)

                    timelineCard(entry: entry, width: cardWidth)
                        .position(x: cardX, y: pointY)
                }
            }
            .frame(width: proxy.size.width, height: totalHeight, alignment: .topLeading)
        }
        .frame(height: max(totalHeight, 120))
    }

    private var timelineNode: some View {
        Circle()
            .fill(Color(hex: "FF6B9D"))
            .frame(width: nodeSize, height: nodeSize)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: Color(hex: "FF6B9D").opacity(0.28), radius: 5, x: 0, y: 2)
    }

    private func timelineCard(entry: Entry, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "F3EEF5"))

                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "A9A2AA"))

                Image(entry.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.dateText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "2F2F33"))
                Text(entry.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "7D7D85"))
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Text("\(entry.score)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "FF5C95"))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(hex: "FFF0F5"))
                .cornerRadius(9)
        }
        .padding(10)
        .frame(width: width, alignment: .leading)
        .background(Color(hex: "FAF8FB"))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "F2E8EF"), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func zigZagPath(leftX: CGFloat, rightX: CGFloat) -> some View {
        Path { path in
            guard entries.count > 1 else { return }

            func point(for index: Int) -> CGPoint {
                CGPoint(
                    x: index.isMultiple(of: 2) ? leftX : rightX,
                    y: topInset + (CGFloat(index) * rowSpacing)
                )
            }

            path.move(to: point(for: 0))

            for index in 1..<entries.count {
                let previous = point(for: index - 1)
                let current = point(for: index)
                let controlOffset: CGFloat = 34
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: previous.x, y: previous.y + controlOffset),
                    control2: CGPoint(x: current.x, y: current.y - controlOffset)
                )
            }
        }
        .stroke(
            LinearGradient(
                colors: [Color(hex: "FF6B9D").opacity(0.7), Color(hex: "FFB4C8").opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            ),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
    }
}

struct TimelinePhotoItem: View {
    let imageName: String
    let date: String
    let label: String
    let score: Int
    
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "FF5C95"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "F7D7E4"), lineWidth: 1)
                    )
                    .cornerRadius(8)

                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                    Circle()
                        .fill(Color(hex: "FF5C95"))
                        .frame(width: 8, height: 8)
                }
            }
            .zIndex(1)
            
            VStack(spacing: 8) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 3)
                
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    Text(date)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "8A8A92"))
                }
            }
        }
    }
}

struct TimelineConnector: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: "E0E0E0"))
            .frame(width: 40, height: 2)
            .padding(.top, 6)
    }
}

struct BeforeAfterSlider: View {
    let beforeImage: Image
    let afterImage: Image
    let beforeLabel: String
    let afterLabel: String

    @State private var sliderPosition: CGFloat = 0.5

    private let minSliderPosition: CGFloat = 0.08
    private let maxSliderPosition: CGFloat = 0.92
    
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let sliderX = width * sliderPosition

            ZStack(alignment: .leading) {
                afterImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                
                beforeImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .mask(
                        Rectangle()
                            .frame(width: sliderX)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )

                HStack {
                    sliderTag(beforeLabel, background: Color.black.opacity(0.62))
                    Spacer()
                    sliderTag(afterLabel, background: Color(hex: "FF5C95").opacity(0.88))
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .top)

                Rectangle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 2, height: geometry.size.height)
                    .offset(x: sliderX - 1)

                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.black.opacity(0.22), radius: 5, x: 0, y: 2)
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "FF5C95"))
                    )
                    .position(x: sliderX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = value.location.x / width
                        sliderPosition = min(max(ratio, minSliderPosition), maxSliderPosition)
                    }
            )
        }
    }

    private func sliderTag(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background)
            .cornerRadius(10)
    }
}

struct StarryBackground: View {
    var body: some View {
        ZStack {
            Color(hex: "151520") // Deep night
            
            // Fixed stars to avoid jitter
            Circle().fill(Color.white.opacity(0.6)).frame(width: 2).offset(x: -100, y: -50)
            Circle().fill(Color.white.opacity(0.4)).frame(width: 3).offset(x: 120, y: 80)
            Circle().fill(Color.white.opacity(0.7)).frame(width: 2).offset(x: -60, y: 120)
            Circle().fill(Color.white.opacity(0.5)).frame(width: 2).offset(x: 80, y: -90)
            Circle().fill(Color.white.opacity(0.3)).frame(width: 1).offset(x: 0, y: 0)
            Circle().fill(Color.white.opacity(0.6)).frame(width: 2).offset(x: 150, y: -20)
            Circle().fill(Color.white.opacity(0.4)).frame(width: 2).offset(x: -140, y: 40)
            Circle().fill(Color.white.opacity(0.8)).frame(width: 3).offset(x: 40, y: -120)
            
            // Moon/Glow effect
            Circle().fill(Color(hex: "9B6BFF").opacity(0.1)).frame(width: 200).offset(x: 100, y: -100).blur(radius: 50)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct SkinView_Previews: PreviewProvider {
    static var previews: some View {
        SkinView()
    }
}
