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
                            currentScreen = .guestChat
                        }
                    }
                })
                
            case .guestChat:
                GuestChatView(onBack: {
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
                        if shouldShowPostOnboardingPaywall && !SubscriptionManager.shared.isPremium {
                            currentScreen = .miniPaywall
                        } else {
                            currentScreen = .results
                        }
                    }
                }

            case .miniPaywall:
                MiniPostOnboardingPaywallView(
                    onUpgradeSuccess: {
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
                var analyzeProfile = parsed
                analyzeProfile.photos = []
                // Pass userId so the server auto-saves the product-enriched routine
                let result = try await APIService.shared.analyze(profile: analyzeProfile, userId: currentUserId)
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
    case guestChat
    case intake
    case analyzing
    case miniPaywall
    case results
}

// MARK: - Guest Chat

private struct GuestChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let content: String
}

struct GuestChatView: View {
    let onBack: () -> Void

    @State private var messages: [GuestChatMessage] = []
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var scrollTick = 0
    @FocusState private var isInputFocused: Bool

    private var welcomeMessage: String {
        """
        Hi, I’m your GlowUp guest assistant.

        I can answer basic skincare questions with short context, but guest mode does not save chat history.

        Create an account for personalized routines and progress tracking. GlowUp+ ($1.99/mo) adds enhanced AI help, smart price scouting, free shipping perks, and expanded catalog access.
        """
    }

    var body: some View {
        ZStack {
            Color(hex: "FDF6F8").ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Sign In")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "FF6B9D"))
                    }

                    Spacer()

                    Text("Guest Chat")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "2D2D2D"))

                    Spacer()

                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "DDDDDD"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                VStack(spacing: 10) {
                    Text("Basic mode: short-context skincare Q&A")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "7A7A7A"))
                    Text("No saved history in guest mode")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "AAAAAA"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "F0E2E8"), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                guestBubble(message)
                                    .id(message.id)
                            }
                            if isTyping {
                                typingIndicator
                                    .id("typing")
                            }
                            Spacer(minLength: 90)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: isTyping) { _, _ in
                        if isTyping { scrollToBottom(proxy) }
                    }
                    .onChange(of: scrollTick) { _, _ in
                        scrollToBottom(proxy)
                    }
                }

                VStack(spacing: 0) {
                    Divider().opacity(0.25)
                    HStack(spacing: 10) {
                        TextField("Ask basic skincare questions...", text: $inputText, axis: .vertical)
                            .font(.system(size: 15))
                            .lineLimit(1...5)
                            .focused($isInputFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(
                                    inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color(hex: "DDDDDD")
                                    : Color(hex: "FF6B9D")
                                )
                                .clipShape(Circle())
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTyping)
                        .padding(.trailing, 8)
                    }
                    .background(Color.white)
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color(hex: "EEEEEE"), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "FDF6F8"))

                    Text("Guest chat does not save your conversation.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "BBBBBB"))
                        .padding(.bottom, 6)
                }
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            if messages.isEmpty {
                messages = [GuestChatMessage(role: .assistant, content: welcomeMessage)]
                scrollTick += 1
            }
        }
    }

    @ViewBuilder
    private func guestBubble(_ message: GuestChatMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 50)
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .lineSpacing(5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "FF6B9D"), Color(hex: "FF8AAF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "FFE0EC"))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "FF6B9D"))
                        )
                    Text("GlowUp")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }

                MarkdownView(text: message.content)
                    .padding(.leading, 4)
            }
        }
    }

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Circle()
                .fill(Color(hex: "FFE0EC"))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "FF6B9D"))
                )

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(hex: "CCCCCC"))
                        .frame(width: 7, height: 7)
                        .scaleEffect(isTyping ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.12),
                            value: isTyping
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

            Spacer()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) {
                if isTyping {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isTyping else { return }
        inputText = ""
        isInputFocused = false

        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(GuestChatMessage(role: .user, content: trimmed))
        }
        withAnimation { isTyping = true }

        let apiMessages = messages.suffix(8).map { msg -> [String: String] in
            [
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ]
        }

        Task {
            do {
                let reply = try await APIService.shared.guestChat(messages: apiMessages)
                await MainActor.run {
                    withAnimation { isTyping = false }
                    withAnimation(.easeOut(duration: 0.2)) {
                        messages.append(GuestChatMessage(role: .assistant, content: reply))
                    }
                }
            } catch {
                let fallback = "I’m having trouble connecting right now. Basic skincare starter: gentle cleanser, moisturizer, and SPF 30+ every day. Create an account for personalized help and saved progress."
                await MainActor.run {
                    withAnimation { isTyping = false }
                    withAnimation(.easeOut(duration: 0.2)) {
                        messages.append(GuestChatMessage(role: .assistant, content: fallback))
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
