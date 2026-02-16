import SwiftUI

struct ContentView: View {
    @State private var currentScreen: AppScreen = .loading
    @State private var userProfile = UserProfile()
    @State private var analysisResult: AnalysisResult?
    @State private var currentUserId: String?
    @State private var skinProfileId: String?
    @State private var isCheckingOnboarding = false
    @State private var shouldShowPostOnboardingPaywall = false
    
    var body: some View {
        ZStack {
            switch currentScreen {
            case .loading:
                ZStack {
                    Color(hex: "FFF0F5").ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text("✨")
                            .font(.system(size: 48))
                        ProgressView()
                            .tint(Color(hex: "FF6B9D"))
                    }
                }
                .onAppear { checkExistingSession() }
                
            case .onboarding:
                OnboardingView(onComplete: { userId in
                    if let userId = userId {
                        currentUserId = userId
                        checkServerOnboardedStatus(userId: userId)
                    } else {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            currentScreen = .guestPlaceholder
                        }
                    }
                })
                
            case .guestPlaceholder:
                GuestPlaceholderView(onBack: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        currentScreen = .onboarding
                    }
                })
                
            case .intake:
                IntakeView(
                    profile: $userProfile,
                    onAnalyze: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            currentScreen = .analyzing
                        }
                        saveOnboardingAndAnalyze()
                    },
                    onBack: {
                        withAnimation { currentScreen = .onboarding }
                    }
                )
                
            case .analyzing:
                AnalyzingView(result: $analysisResult) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        if shouldShowPostOnboardingPaywall && !SessionManager.shared.isPremium {
                            currentScreen = .miniPaywall
                        } else {
                            currentScreen = .results
                        }
                    }
                }

            case .miniPaywall:
                MiniPostOnboardingPaywallView(
                    onUpgrade: {
                        SessionManager.shared.isPremium = true
                        shouldShowPostOnboardingPaywall = false
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            currentScreen = .results
                        }
                    },
                    onContinueFree: {
                        shouldShowPostOnboardingPaywall = false
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            currentScreen = .results
                        }
                    }
                )
                
            case .results:
                mainApp
            }
            
            // Loading overlay while checking onboarding
            if isCheckingOnboarding {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Loading your routine...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color(hex: "2D2D2D"))
                    .cornerRadius(16)
                }
            }
        }
    }
    
    @ViewBuilder
    private var mainApp: some View {
        let result = analysisResult ?? AnalysisResult(
            agents: [],
            summary: Summary(
                totalProducts: 0,
                totalCost: 0,
                overallConfidence: "0",
                routine: nil,
                personalized_tips: ["Stay consistent with your routine for the best results."]
            ),
            inference: nil
        )
        MainTabView(analysisResult: result, onSignOut: {
            SessionManager.shared.signOut()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentScreen = .onboarding
            }
        })
    }
    
    // MARK: - Session check
    
    private func checkExistingSession() {
        let savedUserId = SessionManager.shared.userId
        let isOnboarded = SessionManager.shared.isOnboarded
        
        if let userId = savedUserId {
            currentUserId = userId
            if isOnboarded {
                loadExistingRoutine(userId: userId)
            } else {
                checkOnboardingStatus(userId: userId)
            }
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentScreen = .onboarding
            }
        }
    }
    
    // MARK: - Returning user
    
    private func loadExistingRoutine(userId: String) {
        Task {
            do {
                if let routine = try await SupabaseService.shared.getLatestRoutine(userId: userId) {
                    await MainActor.run {
                        analysisResult = routine
                        transitionTo(.results)
                    }
                } else {
                    await MainActor.run { transitionTo(.results) }
                }
            } catch {
                await MainActor.run { transitionTo(.results) }
            }
        }
    }
    
    // MARK: - Onboarding status
    
    private func checkOnboardingStatus(userId: String) {
        isCheckingOnboarding = true
        Task {
            do {
                let onboarded = try await SupabaseService.shared.isUserOnboarded(userId: userId)
                if onboarded {
                    SessionManager.shared.markOnboarded()
                    if let routine = try await SupabaseService.shared.getLatestRoutine(userId: userId) {
                        await MainActor.run {
                            analysisResult = routine
                            isCheckingOnboarding = false
                            transitionTo(.results)
                        }
                        return
                    }
                    await MainActor.run {
                        isCheckingOnboarding = false
                        transitionTo(.results)
                    }
                } else {
                    await MainActor.run {
                        isCheckingOnboarding = false
                        transitionTo(.intake)
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingOnboarding = false
                    transitionTo(.intake)
                }
            }
        }
    }
    
    private func checkServerOnboardedStatus(userId: String) {
        isCheckingOnboarding = true
        Task {
            do {
                let onboarded = try await SupabaseService.shared.isUserOnboarded(userId: userId)
                if onboarded {
                    SessionManager.shared.markOnboarded()
                    if let routine = try await SupabaseService.shared.getLatestRoutine(userId: userId) {
                        await MainActor.run {
                            analysisResult = routine
                            isCheckingOnboarding = false
                            transitionTo(.results)
                        }
                        return
                    }
                    await MainActor.run {
                        isCheckingOnboarding = false
                        transitionTo(.results)
                    }
                } else {
                    await MainActor.run {
                        isCheckingOnboarding = false
                        transitionTo(.intake)
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingOnboarding = false
                    transitionTo(.intake)
                }
            }
        }
    }
    
    // MARK: - Onboarding + Analysis
    
    private func saveOnboardingAndAnalyze() {
        Task {
            do {
                if let userId = currentUserId {
                    let parsed = userProfile.normalized()
                    await MainActor.run { self.userProfile = parsed }
                    let savedProfile = try await SupabaseService.shared.saveSkinProfile(userId: userId, profile: parsed)
                    skinProfileId = savedProfile?.id
                }
                
                let parsed = userProfile.normalized()
                // Pass userId so the server auto-saves the product-enriched routine
                let result = try await APIService.shared.analyze(profile: parsed, userId: currentUserId)
                await MainActor.run { analysisResult = result }
                
                // Server already saved the routine — just mark onboarded locally
                if currentUserId != nil {
                    SessionManager.shared.markOnboarded()
                    shouldShowPostOnboardingPaywall = !SessionManager.shared.isPremium
                }
            } catch {
                // Set placeholder so analyzing screen doesn't hang
                await MainActor.run {
                    if analysisResult == nil {
                        analysisResult = AnalysisResult(
                            agents: [],
                            summary: Summary(
                                totalProducts: 0,
                                totalCost: 0,
                                overallConfidence: "0",
                                routine: nil,
                                personalized_tips: ["Your profile is saved! Explore the app for personalized recommendations."]
                            ),
                            inference: nil
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Navigation helper
    
    private func transitionTo(_ screen: AppScreen) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentScreen = screen
        }
    }
}

enum AppScreen {
    case loading
    case onboarding
    case guestPlaceholder
    case intake
    case analyzing
    case miniPaywall
    case results
}

// MARK: - Guest Placeholder

struct GuestPlaceholderView: View {
    let onBack: () -> Void
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FFF0F5"), Color(hex: "FFE4EC"), Color(hex: "FFD6E5")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 120, height: 120)
                        .shadow(color: Color(hex: "FF6B9D").opacity(0.2), radius: 20, x: 0, y: 10)
                    Text("🔐")
                        .font(.system(size: 48))
                }
                
                VStack(spacing: 16) {
                    Text("Sign In Required")
                        .font(.custom("Didot", size: 28))
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    Text("To get personalized skincare recommendations,\nplease sign in with your Apple ID.")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "666666"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }
                
                Spacer()
                
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                        Text("Back to Sign In")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "FF6B9D"))
                    .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
    }
}

#Preview {
    ContentView()
}
