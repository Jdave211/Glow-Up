import SwiftUI

struct ContentView: View {
    @State private var currentScreen: AppScreen = .loading
    @State private var userProfile = UserProfile()
    @State private var analysisResult: AnalysisResult?
    @State private var currentUserId: String?
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
                        resolveSignedInUserLaunchState(userId: userId)
                    } else {
                        beginGuestChatFlow()
                    }
                })

            case .guestConsent:
                AIDataConsentScreen(
                    kind: .chat,
                    onAccept: {
                        SessionManager.shared.hasAIDataConsent = true
                        transitionTo(.guestChat)
                    },
                    onCancel: {
                        transitionTo(.onboarding)
                    }
                )
                
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
                        beginAnalysisFlow()
                    },
                    onBack: {
                        withAnimation { currentScreen = .onboarding }
                    }
                )

            case .faceConsent:
                AIDataConsentScreen(
                    kind: .faceAnalysis,
                    onAccept: {
                        SessionManager.shared.hasAIDataConsent = true
                        SessionManager.shared.hasFaceAnalysisConsent = true
                        startAnalyzingFlow()
                    },
                    onCancel: {
                        transitionTo(.intake)
                    }
                )
                
            case .analyzing:
                AnalyzingView(result: $analysisResult) {
                    transitionTo(.analysisSummary)
                }

            case .analysisSummary:
                ResultsView(
                    result: currentAnalysisResult,
                    onRestart: {
                        shouldShowPostOnboardingPaywall = false
                        transitionTo(.intake)
                    },
                    continueButtonTitle: "Open My Glow",
                    onContinue: {
                        if shouldShowPostOnboardingPaywall && !SubscriptionManager.shared.isPremium {
                            transitionTo(.miniPaywall)
                        } else {
                            transitionTo(.results)
                        }
                    }
                )

            case .results:
                mainApp

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
        MainTabView(analysisResult: currentAnalysisResult, onSignOut: {
            SessionManager.shared.signOut()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentScreen = .onboarding
            }
        })
    }

    private var currentAnalysisResult: AnalysisResult {
        analysisResult ?? AnalysisResult(
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
    }
    
    // MARK: - Session check
    
    private func checkExistingSession() {
        let savedUserId = SessionManager.shared.userId
        
        if let userId = savedUserId {
            currentUserId = userId
            resolveSignedInUserLaunchState(userId: userId)
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentScreen = .onboarding
            }
        }
    }
    
    // MARK: - Session routing

    private func resolveSignedInUserLaunchState(userId: String) {
        let localOnboarded = SessionManager.shared.isOnboarded
        isCheckingOnboarding = true

        Task {
            async let onboardedRequest = try? SupabaseService.shared.isUserOnboarded(userId: userId)
            async let routineRequest = try? SupabaseService.shared.getLatestRoutine(userId: userId)

            let serverOnboarded = await onboardedRequest ?? false
            let latestRoutine = await routineRequest ?? nil

            await MainActor.run {
                isCheckingOnboarding = false

                if let routine = latestRoutine {
                    analysisResult = routine
                    SessionManager.shared.markOnboarded()
                    transitionTo(.results)
                    return
                }

                if serverOnboarded || localOnboarded {
                    if serverOnboarded {
                        SessionManager.shared.markOnboarded()
                    }
                    transitionTo(.results)
                    return
                }

                transitionTo(.intake)
            }
        }
    }
    
    // MARK: - Onboarding + Analysis

    private func beginGuestChatFlow() {
        if SessionManager.shared.hasAIDataConsent {
            transitionTo(.guestChat)
        } else {
            transitionTo(.guestConsent)
        }
    }

    private func beginAnalysisFlow() {
        let parsed = userProfile.normalized()
        userProfile = parsed

        if SessionManager.shared.hasFaceAnalysisConsent {
            startAnalyzingFlow()
        } else {
            transitionTo(.faceConsent)
        }
    }

    private func startAnalyzingFlow() {
        transitionTo(.analyzing)
        saveOnboardingAndAnalyze()
    }
    
    private func saveOnboardingAndAnalyze() {
        Task {
            do {
                if let userId = currentUserId {
                    let parsed = userProfile.normalized()
                    await MainActor.run { self.userProfile = parsed }
                    let savedProfile = try await SupabaseService.shared.saveSkinProfile(userId: userId, profile: parsed)
                    let savedProfileId = savedProfile?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !savedProfileId.isEmpty {
                        SessionManager.shared.skinProfileId = savedProfileId
                    }
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
    case guestConsent
    case guestChat
    case intake
    case faceConsent
    case analyzing
    case analysisSummary
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
    @State private var pendingMessageAfterConsent: String?
    @State private var showConsentSheet = false
    @FocusState private var isInputFocused: Bool

    private var welcomeMessage: String {
        """
        Hi, I’m your GlowUp guest assistant.

        I can answer basic looksmaxing questions (skin-first, plus hair/smile basics) with short context, but guest mode does not save chat history.

        Create an account to upload photos and get a personalized glow-up plan. GlowUp+ ($1.99/mo) adds deeper recommendation quality, objective technique guidance, and stronger product matching.
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
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }

                VStack(spacing: 10) {
                    Text("Basic mode: short-context looksmaxing Q&A")
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
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }

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
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture { isInputFocused = false }
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
                        TextField("Ask basic looksmaxing questions...", text: $inputText, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "2D2D2D"))
                            .lineLimit(1...5)
                            .focused($isInputFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                        Button(action: { send() }) {
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
        .sheet(isPresented: $showConsentSheet) {
            AIDataConsentScreen(
                kind: .chat,
                onAccept: {
                    SessionManager.shared.hasAIDataConsent = true
                    showConsentSheet = false
                    if let pendingMessageAfterConsent {
                        send(messageOverride: pendingMessageAfterConsent)
                    }
                },
                onCancel: {
                    pendingMessageAfterConsent = nil
                    showConsentSheet = false
                }
            )
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

    private func send(messageOverride: String? = nil) {
        let trimmed = (messageOverride ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isTyping else { return }
        guard SessionManager.shared.hasAIDataConsent else {
            pendingMessageAfterConsent = trimmed
            showConsentSheet = true
            return
        }

        pendingMessageAfterConsent = nil
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
                let fallback = "I’m having trouble connecting right now. Quick looksmaxing starter: gentle cleanser, moisturizer, SPF 30+, sleep consistency, and hydration. Create an account for personalized photo-driven guidance."
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

enum AIConsentKind {
    case chat
    case faceAnalysis

    var title: String {
        switch self {
        case .chat:
            return "AI Chat Permission"
        case .faceAnalysis:
            return "Face Data Permission"
        }
    }

    var subtitle: String {
        switch self {
        case .chat:
            return "GlowUp needs your permission before sending personal data to third-party AI processing."
        case .faceAnalysis:
            return "GlowUp needs explicit permission before analyzing face photos and related skin-profile data."
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .chat:
            return "Allow AI Chat"
        case .faceAnalysis:
            return "Allow Face Analysis"
        }
    }

    var disclosureItems: [String] {
        switch self {
        case .chat:
            return [
                "Data sent: your chat message, plus your saved routine and profile context when needed for a reply.",
                "Recipients: GlowUp's backend, Supabase for conversation storage, and OpenAI for AI-generated responses.",
                "Storage: GlowUp stores your signed-in chat history so it appears across sessions. Guest mode does not save chat history."
            ]
        case .faceAnalysis:
            return [
                "Face data sent: the photos you select, your skin-profile answers, and derived face/skin analysis signals.",
                "Recipients: GlowUp's backend, private Supabase storage for photos, and OpenAI for photo-driven analysis.",
                "Retention: if Photo Check-ins is on, private photos are retained for up to 90 days for progress tracking; if it is off, uploaded raw photos are deleted after analysis and only derived analysis results remain."
            ]
        }
    }
}

struct AIDataConsentCard: View {
    let kind: AIConsentKind
    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Circle()
                .fill(Color(hex: "FFE8F1"))
                .frame(width: 68, height: 68)
                .overlay(
                    Image(systemName: kind == .faceAnalysis ? "faceid" : "sparkles")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                )

            VStack(spacing: 8) {
                Text(kind.title)
                    .font(.custom("Didot", size: 30))
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "2D2D2D"))

                Text(kind.subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "666666"))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(kind.disclosureItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                            .padding(.top, 2)

                        Text(item)
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "444444"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(hex: "F3DDE7"), lineWidth: 1)
            )

            VStack(spacing: 10) {
                Button(action: onAccept) {
                    Text(kind.primaryButtonTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: "FF6B9D"))
                        .cornerRadius(16)
                }

                Button(action: onCancel) {
                    Text("Not Now")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "7A7A7A"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.85))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "E9E1E5"), lineWidth: 1)
                        )
                }
            }
        }
        .padding(22)
        .background(Color(hex: "FFF8FB"))
        .cornerRadius(28)
        .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 10)
    }
}

struct AIDataConsentScreen: View {
    let kind: AIConsentKind
    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FFF3F7"), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                AIDataConsentCard(kind: kind, onAccept: onAccept, onCancel: onCancel)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
