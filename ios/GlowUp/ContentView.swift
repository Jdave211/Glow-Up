import SwiftUI

struct ContentView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var currentScreen: AppScreen = .loading
    @State private var userProfile = UserProfile()
    @State private var analysisResult: AnalysisResult?
    @State private var currentUserId: String?
    @State private var isCheckingOnboarding = false
    @State private var pendingMainTabOverride: MainTabView.Tab?
    @State private var pendingSkinTabOverride: SkinView.SkinTab?
    @State private var shouldRouteToRoutineAfterPaywallUnlock = false
    
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
                    currentUserId = userId
                    resolveSignedInUserLaunchState(userId: userId)
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
                    onCancel: nil
                )
                
            case .analyzing:
                AnalyzingView(result: $analysisResult) {
                    handleOnboardingAnalysisComplete()
                }

            case .results:
                if subscriptionManager.isPremium {
                    mainApp
                } else {
                    premiumGate
                }

            case .miniPaywall:
                premiumGate
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
        .onChange(of: subscriptionManager.isPremium) { _, isPremium in
            if isPremium && currentScreen == .miniPaywall {
                handlePaywallUnlockSuccess()
            } else if !subscriptionManager.isPremium && currentScreen == .results && SessionManager.shared.isOnboarded {
                shouldRouteToRoutineAfterPaywallUnlock = false
                transitionTo(.miniPaywall)
            }
        }
    }
    
    @ViewBuilder
    private var mainApp: some View {
        MainTabView(
            analysisResult: currentAnalysisResult,
            initialTab: pendingMainTabOverride ?? .home,
            initialSkinTab: pendingSkinTabOverride ?? .progress,
            onSignOut: {
                SessionManager.shared.signOut()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    currentScreen = .onboarding
                }
            }
        )
        .onAppear {
            consumePendingLaunchOverrideIfNeeded()
        }
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

    private var premiumGate: some View {
        PremiumPaywallView(
            isDismissible: false,
            onUpgradeSuccess: {
                handlePaywallUnlockSuccess()
            }
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
            await SubscriptionManager.shared.refreshEntitlements()

            await MainActor.run {
                isCheckingOnboarding = false

                if let routine = latestRoutine {
                    analysisResult = routine
                    SessionManager.shared.markOnboarded()
                    if subscriptionManager.isPremium {
                        transitionTo(.results)
                    } else {
                        shouldRouteToRoutineAfterPaywallUnlock = false
                        transitionTo(.miniPaywall)
                    }
                    return
                }

                if serverOnboarded || localOnboarded {
                    if serverOnboarded {
                        SessionManager.shared.markOnboarded()
                    }
                    if subscriptionManager.isPremium {
                        transitionTo(.results)
                    } else {
                        shouldRouteToRoutineAfterPaywallUnlock = false
                        transitionTo(.miniPaywall)
                    }
                    return
                }

                transitionTo(.intake)
            }
        }
    }
    
    // MARK: - Onboarding + Analysis

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
    
    private func handleOnboardingAnalysisComplete() {
        if subscriptionManager.isPremium {
            stagePostOnboardingDestination()
            transitionTo(.results)
        } else {
            shouldRouteToRoutineAfterPaywallUnlock = true
            transitionTo(.miniPaywall)
        }
    }

    private func handlePaywallUnlockSuccess() {
        if shouldRouteToRoutineAfterPaywallUnlock {
            stagePostOnboardingDestination()
            shouldRouteToRoutineAfterPaywallUnlock = false
        }
        transitionTo(.results)
    }

    private func stagePostOnboardingDestination() {
        pendingMainTabOverride = .skin
        pendingSkinTabOverride = .routine
    }

    private func consumePendingLaunchOverrideIfNeeded() {
        guard pendingMainTabOverride != nil || pendingSkinTabOverride != nil else { return }
        DispatchQueue.main.async {
            pendingMainTabOverride = nil
            pendingSkinTabOverride = nil
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
    case intake
    case faceConsent
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
    @State private var pendingMessageAfterConsent: String?
    @State private var showConsentSheet = false
    @FocusState private var isInputFocused: Bool

    private var welcomeMessage: String {
        """
        Hi, I’m your GlowUp guest assistant.

        I can answer basic looksmaxing questions (skin-first, plus hair/smile basics) with short context, but guest mode does not save chat history.

        Create an account to upload photos and get a personalized glow-up plan. GlowUp+ ($2.99/week or $6.99/month) adds deeper recommendation quality, objective technique guidance, and stronger product matching.
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
            return "Face Analysis"
        }
    }

    var subtitle: String {
        switch self {
        case .chat:
            return "GlowUp needs your permission before sending personal data to third-party AI processing."
        case .faceAnalysis:
            return "Your photos are used only to personalize your routine and skin analysis."
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .chat:
            return "Allow AI Chat"
        case .faceAnalysis:
            return "Continue"
        }
    }

    var secondaryButtonTitle: String? {
        switch self {
        case .chat:
            return "Not Now"
        case .faceAnalysis:
            return nil
        }
    }

    var disclosureItems: [String] {
        switch self {
        case .chat:
            return [
                "Data sent: your chat message, plus your saved routine and profile context when needed for a reply.",
                "Recipients: GlowUp's backend, Supabase for conversation storage, and OpenAI for AI-generated responses.",
                "Storage: GlowUp stores your signed-in chat history so it appears across sessions, and you can delete chats from the app at any time."
            ]
        case .faceAnalysis:
            return [
                "We never sell your face photos or use them for advertising."
            ]
        }
    }

    var iconName: String {
        switch self {
        case .chat:
            return "sparkles"
        case .faceAnalysis:
            return "faceid"
        }
    }
}

struct AIDataConsentCard: View {
    let kind: AIConsentKind
    let onAccept: () -> Void
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 74, height: 74)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.75), lineWidth: 1)
                    )

                Image(systemName: kind.iconName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(Color(hex: "FF6B9D"))
            }

            VStack(spacing: 8) {
                Text(kind.title)
                    .font(.custom("Didot", size: 34))
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "242638"))

                Text(kind.subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "54576A"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            if !kind.disclosureItems.isEmpty {
                VStack(alignment: .leading, spacing: kind == .faceAnalysis ? 8 : 12) {
                    ForEach(kind.disclosureItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(hex: "FF6B9D"))
                                .padding(.top, 1)

                            Text(item)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "3D3F51"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.42))
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.65), lineWidth: 1)
                )
            }

            VStack(spacing: 10) {
                Button(action: onAccept) {
                    Text(kind.primaryButtonTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "FF5C95"), Color(hex: "FF79A9")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color(hex: "FF5C95").opacity(0.28), radius: 10, x: 0, y: 5)
                }

                if let cancelTitle = kind.secondaryButtonTitle, let onCancel {
                    Button(action: onCancel) {
                        Text(cancelTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "70758C"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.55))
                            .background(.ultraThinMaterial)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color(hex: "FFDCEB").opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )
        )
        .shadow(color: Color(hex: "8C5A7A").opacity(0.18), radius: 24, x: 0, y: 12)
    }
}

struct AIDataConsentScreen: View {
    let kind: AIConsentKind
    let onAccept: () -> Void
    let onCancel: (() -> Void)?

    init(kind: AIConsentKind, onAccept: @escaping () -> Void, onCancel: (() -> Void)? = nil) {
        self.kind = kind
        self.onAccept = onAccept
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "F8DCEC"), Color(hex: "F8ECF9"), Color(hex: "FFF6FA")],
                startPoint: .topLeading,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.32))
                .frame(width: 260, height: 260)
                .blur(radius: 14)
                .offset(x: -110, y: -240)

            Circle()
                .fill(Color(hex: "FFC7DF").opacity(0.36))
                .frame(width: 220, height: 220)
                .blur(radius: 18)
                .offset(x: 130, y: 290)

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
