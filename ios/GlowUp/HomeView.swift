import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════
// MARK: - HomeViewModel (fetches from fine-tuned model)
// ═══════════════════════════════════════════════════

class HomeViewModel: ObservableObject {
    @Published var feed: HomeFeedResponse?
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var errorMessage: String?
    @Published var livePickedForYou: [FeedProduct] = []
    @Published var isRefreshingPickedForYou = false
    
    private var pickedForYouTargetCount = 0
    private var replacementCooldownUntil: Date = .distantPast
    private var recentReplacementIds: [String] = []
    
    // Sections
    var pickedForYou: [FeedProduct] { livePickedForYou }
    var trending: [FeedProduct] { feed?.sections.trending ?? [] }
    var newArrivals: [FeedProduct] { feed?.sections.new_arrivals ?? [] }
    var morningSteps: [FeedRoutineStep] { feed?.routine?.morning ?? [] }
    var eveningSteps: [FeedRoutineStep] { feed?.routine?.evening ?? [] }
    var weeklySteps: [FeedRoutineStep] { feed?.routine?.weekly ?? [] }
    var routineHasProducts: Bool { feed?.routine_has_products ?? false }
    var tips: [String] { feed?.tips ?? [] }
    var summary: String { feed?.user_summary ?? "Your personalized glow-up awaits ✨" }
    
    func loadFeed(force: Bool = false) {
        guard let userId = SessionManager.shared.userId else {
            errorMessage = "Sign in to see your personalized feed"
            return
        }
        guard !isLoading else { return }
        if hasLoaded && !force { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await APIService.shared.fetchHomeFeed(userId: userId)
                await MainActor.run {
                    self.feed = result
                    self.livePickedForYou = result.sections.picked_for_you
                    self.pickedForYouTargetCount = max(result.sections.picked_for_you.count, 4)
                    self.isLoading = false
                    self.hasLoaded = true
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Couldn't load your feed — pull to retry"
                    #if DEBUG
                    print("❌ Home feed error: \(error)")
                    #endif
                }
            }
        }
    }
    
    func refresh() {
        loadFeed(force: true)
    }
    
    func replacePickedForYouAfterAddToCart(_ addedProduct: FeedProduct, cartProductIds: Set<String>) {
        guard let slotIndex = livePickedForYou.firstIndex(where: { $0.id == addedProduct.id }) else { return }
        
        let existingIds = Set(livePickedForYou.map(\.id))
        var exclusion = existingIds.union(cartProductIds)
        exclusion.insert(addedProduct.id)
        
        if let localFallback = localFallbackReplacement(excluding: exclusion) {
            livePickedForYou[slotIndex] = localFallback
            exclusion.insert(localFallback.id)
        } else {
            livePickedForYou.remove(at: slotIndex)
        }
        
        Task {
            await self.fillPickedForYouSlot(
                preferredIndex: slotIndex,
                baseProduct: addedProduct,
                cartProductIds: cartProductIds,
                force: true
            )
        }
    }
    
    func maybeDynamicallyRefreshPickedForYou(cartProductIds: Set<String>) {
        guard hasLoaded, !livePickedForYou.isEmpty, !isRefreshingPickedForYou else { return }
        guard Date() >= replacementCooldownUntil else { return }
        
        let candidates = livePickedForYou.enumerated().filter { !cartProductIds.contains($0.element.id) }
        guard let target = candidates.randomElement() else { return }
        
        replacementCooldownUntil = Date().addingTimeInterval(25)
        Task {
            await self.fillPickedForYouSlot(
                preferredIndex: target.offset,
                baseProduct: target.element,
                cartProductIds: cartProductIds,
                force: false
            )
        }
    }
    
    func ensurePickedForYouExcludesCart(cartProductIds: Set<String>) {
        guard !livePickedForYou.isEmpty else { return }
        guard let cartProduct = livePickedForYou.first(where: { cartProductIds.contains($0.id) }) else { return }
        replacePickedForYouAfterAddToCart(cartProduct, cartProductIds: cartProductIds)
    }
    
    private func fillPickedForYouSlot(
        preferredIndex: Int,
        baseProduct: FeedProduct,
        cartProductIds: Set<String>,
        force: Bool
    ) async {
        await MainActor.run { self.isRefreshingPickedForYou = true }
        defer {
            Task { @MainActor in
                self.isRefreshingPickedForYou = false
            }
        }
        
        guard let userId = SessionManager.shared.userId else { return }
        
        let query = replacementQuery(for: baseProduct)
        let recentIds = await MainActor.run { Set(self.recentReplacementIds.suffix(24)) }
        let currentIds = await MainActor.run { Set(self.livePickedForYou.map(\.id)) }
        let exclusion = currentIds.union(cartProductIds).union(recentIds).union([baseProduct.id])
        
        do {
            let fetched = try await APIService.shared.searchRoutineProducts(
                userId: userId,
                query: query,
                category: baseProduct.category,
                limit: 20
            )
            let replacement = fetched.first { !exclusion.contains($0.id) }
            guard let replacement else { return }
            
            await MainActor.run {
                var list = self.livePickedForYou
                let currentIndex = list.firstIndex(where: { $0.id == baseProduct.id }) ?? min(preferredIndex, max(list.count - 1, 0))
                
                if list.isEmpty {
                    list = [replacement]
                } else if currentIndex >= 0 && currentIndex < list.count {
                    list[currentIndex] = replacement
                } else {
                    list.append(replacement)
                }
                
                while list.count > max(self.pickedForYouTargetCount, 4) {
                    list.removeLast()
                }
                
                self.livePickedForYou = list
                self.recentReplacementIds.append(replacement.id)
                if self.recentReplacementIds.count > 80 {
                    self.recentReplacementIds.removeFirst(self.recentReplacementIds.count - 80)
                }
            }
        } catch {
            if force {
                #if DEBUG
                print("⚠️ Picked-for-you DB replacement failed: \(error)")
                #endif
            }
        }
    }
    
    private func localFallbackReplacement(excluding exclusion: Set<String>) -> FeedProduct? {
        let fallbackPool = (trending + newArrivals).filter { !exclusion.contains($0.id) }
        return fallbackPool.first
    }
    
    private func replacementQuery(for product: FeedProduct) -> String {
        if let concerns = product.target_concerns, let first = concerns.first, !first.isEmpty {
            return "\(first) skincare"
        }
        if !product.category.isEmpty {
            return "\(product.category) skincare"
        }
        let namePrefix = product.name.split(separator: " ").prefix(2).joined(separator: " ")
        return namePrefix.isEmpty ? "skincare routine" : "\(namePrefix) skincare"
    }
}

// ═══════════════════════════════════════════════════
// MARK: - HomeView
// ═══════════════════════════════════════════════════

struct HomeView: View {
    @ObservedObject var cartManager: CartManager
    @StateObject private var viewModel = HomeViewModel()
    @State private var showingProductDetail: InferenceProduct?
    @State private var showingRoutineDetail: RoutineType?
    @State private var completedSteps: Set<String> = []
    @State private var streaks: (morning: Int, evening: Int) = (0, 0)
    @State private var showingQuickBuy = false
    private let pickedForYouRefreshTimer = Timer.publish(every: 35, on: .main, in: .common).autoconnect()
    
    enum RoutineType: Identifiable {
        case morning
        case evening
        case weekly
        
        var id: String {
            switch self {
            case .morning: return "morning"
            case .evening: return "evening"
            case .weekly: return "weekly"
            }
        }
    }
    
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        else if hour < 18 { return "Good afternoon" }
        else { return "Good evening" }
    }
    
    private var firstName: String {
        let raw = (SessionManager.shared.userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        
        // Handle email-like names by using local-part, otherwise use first token.
        let seed = raw.contains("@")
            ? String(raw.split(separator: "@").first ?? "")
            : String(raw.split(separator: " ").first ?? "")
        
        let lettersOnly = seed.filter { $0.isLetter || $0 == "-" || $0 == "'" }
        guard !lettersOnly.isEmpty else { return "" }
        return lettersOnly.prefix(1).uppercased() + lettersOnly.dropFirst().lowercased()
    }
    
    private var greetingWithName: String {
        guard !firstName.isEmpty else { return greeting }
        return "\(greeting), \(firstName)"
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                headerView
                
                if viewModel.isLoading && !viewModel.hasLoaded {
                    // Shimmer loading state
                    shimmerView
                } else if viewModel.hasLoaded {
                    // Dynamic feed from fine-tuned model
                    feedContent
                } else if let error = viewModel.errorMessage {
                    // Error state with retry
                    VStack(spacing: 20) {
                        Spacer().frame(height: 40)
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(Color(hex: "FFB4C8"))
                        Text(error)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "888888"))
                            .multilineTextAlignment(.center)
                        Button(action: { viewModel.loadFeed(force: true) }) {
                            Text("Try Again")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(Color(hex: "FF6B9D"))
                                .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer(minLength: 100)
            }
            .padding(.top, 12)
        }
        .refreshable {
            viewModel.refresh()
            // Small delay so the pull-to-refresh animation feels natural
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        .background(PinkDrapeBackground().ignoresSafeArea())
        .sheet(item: $showingProductDetail) { product in
            ProductDetailSheet(product: product, cartManager: cartManager, fit: nil, showFullFit: false)
        }
        .onAppear {
            viewModel.loadFeed()
            loadCheckins()
            viewModel.ensurePickedForYouExcludesCart(cartProductIds: cartProductIds())
        }
        .onReceive(pickedForYouRefreshTimer) { _ in
            viewModel.maybeDynamicallyRefreshPickedForYou(cartProductIds: cartProductIds())
        }
        .onChange(of: cartManager.itemCount) { _, _ in
            viewModel.ensurePickedForYouExcludesCart(cartProductIds: cartProductIds())
        }
        .sheet(isPresented: $showingQuickBuy) {
            QuickBuySheet(cartManager: cartManager)
        }
        .sheet(item: $showingRoutineDetail) { routineType in
            RoutineDetailSheet(
                routineType: routineType,
                steps: routineSteps(for: routineType),
                morningSteps: viewModel.morningSteps,
                eveningSteps: viewModel.eveningSteps,
                weeklySteps: viewModel.weeklySteps,
                completedSteps: $completedSteps,
                streaks: $streaks,
                userId: SessionManager.shared.userId ?? "",
                onRoutineUpdated: {
                    viewModel.refresh()
                }
            )
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Header
    // ─────────────────────────────────────────────
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greetingWithName)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "999999"))
                    
                    Text("Your Glow")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "2D2D2D"))
                }
                
                Spacer()
                
                // Cart badge
                Button(action: { showingQuickBuy = true }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bag")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        
                        if cartManager.itemCount > 0 {
                            Text("\(cartManager.itemCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(Color(hex: "FF6B9D"))
                                .clipShape(Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                
                // Profile avatar
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "FF6B9D"), Color(hex: "FFB4C8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String((SessionManager.shared.userName ?? "G").prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Feed Content (from fine-tuned model)
    // ─────────────────────────────────────────────
    private var feedContent: some View {
        VStack(spacing: 28) {
            // Routine cards
            if !viewModel.morningSteps.isEmpty || !viewModel.eveningSteps.isEmpty {
                routineSection
            }
            
            // Picked For You
            if !viewModel.pickedForYou.isEmpty {
                productSection(
                    title: "Picked For You",
                    subtitle: "Based on your profile",
                    products: viewModel.pickedForYou,
                    accent: Color(hex: "FF6B9D"),
                    onAddToCart: { product in
                        viewModel.replacePickedForYouAfterAddToCart(product, cartProductIds: cartProductIds())
                    }
                )
            }
            
            // Quick insights
            insightsSection
            
            // Trending
            if !viewModel.trending.isEmpty {
                productSection(
                    title: "Trending Now",
                    subtitle: "Top rated products",
                    products: viewModel.trending,
                    accent: Color(hex: "9B6BFF")
                )
            }
            
            // New from Ulta
            if !viewModel.newArrivals.isEmpty {
                productSection(
                    title: "New Arrivals",
                    subtitle: "Fresh from Ulta",
                    products: viewModel.newArrivals,
                    accent: Color(hex: "4ECDC4")
                )
            }
            
            // Daily tip
            if let tip = viewModel.tips.first {
                tipSection(tip)
            }
            
            // More tips
            if viewModel.tips.count > 1 {
                moreTipsSection
            }
            
            // Loading indicator for refresh
            if viewModel.isLoading && viewModel.hasLoaded {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Color(hex: "FF6B9D"))
                    Text("Refreshing your feed...")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "999999"))
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    
    // ─────────────────────────────────────────────
    // MARK: - Routine Section
    // ─────────────────────────────────────────────
    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Your Routine")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let morningComplete = isRoutineComplete(.morning)
                    RoutineTallCard(
                        title: "Morning\nGlow",
                        subtitle: morningComplete ? "🔥 \(streaks.morning) day streak" : "\(viewModel.morningSteps.count) steps",
                        icon: "sun.max.fill",
                        gradient: LinearGradient(
                            colors: morningComplete ? 
                                [Color(hex: "FFD4E5"), Color(hex: "FFE8F0")] :
                                [Color(hex: "FFE0EC"), Color(hex: "FFF5F8")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        accent: Color(hex: "FF6B9D"),
                        isComplete: morningComplete
                    )
                    .onTapGesture {
                        showingRoutineDetail = .morning
                    }
                    
                    let eveningComplete = isRoutineComplete(.evening)
                    RoutineTallCard(
                        title: "Evening\nRepair",
                        subtitle: eveningComplete ? "🔥 \(streaks.evening) day streak" : "\(viewModel.eveningSteps.count) steps",
                        icon: "moon.stars.fill",
                        gradient: LinearGradient(
                            colors: eveningComplete ?
                                [Color(hex: "E0D4FF"), Color(hex: "F0E8FF")] :
                                [Color(hex: "E8E0FF"), Color(hex: "F5F0FF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        accent: Color(hex: "9B6BFF"),
                        isComplete: eveningComplete
                    )
                    .onTapGesture {
                        showingRoutineDetail = .evening
                    }
                    
                    RoutineTallCard(
                        title: "Weekly\nReset",
                        subtitle: viewModel.weeklySteps.isEmpty ? "Treatments" : "\(viewModel.weeklySteps.count) steps",
                        icon: "sparkles",
                        gradient: LinearGradient(
                            colors: [Color(hex: "E0F5F0"), Color(hex: "F0FAF8")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        accent: Color(hex: "4ECDC4")
                    )
                    .onTapGesture {
                        showingRoutineDetail = .weekly
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Product Section (reusable)
    // ─────────────────────────────────────────────
    private func productSection(
        title: String,
        subtitle: String,
        products: [FeedProduct],
        accent: Color,
        onAddToCart: ((FeedProduct) -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "999999"))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(products) { product in
                        ProductSquareCard(
                            product: product.asInferenceProduct,
                            isInCart: cartManager.contains(productId: product.id)
                        ) {
                            showingProductDetail = product.asInferenceProduct
                        } onAddToCart: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            cartManager.addToCart(product.asInferenceProduct)
                            onAddToCart?(product)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Quick Insights
    // ─────────────────────────────────────────────
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Quick Insights", action: nil)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    InsightPill(
                        title: "Skin Score",
                        value: "\(Int((viewModel.feed?.confidence ?? 0.85) * 100))",
                        icon: "face.smiling",
                        bg: Color(hex: "FFF0F5"),
                        fg: Color(hex: "FF6B9D")
                    )
                    
                    InsightPill(
                        title: "Matched",
                        value: "\(viewModel.pickedForYou.count)",
                        icon: "checkmark.seal.fill",
                        bg: Color(hex: "E8FAF8"),
                        fg: Color(hex: "4ECDC4")
                    )
                    
                    InsightPill(
                        title: "Routine",
                        value: "\(max(viewModel.morningSteps.count + viewModel.eveningSteps.count + viewModel.weeklySteps.count, 0))",
                        icon: "sparkles",
                        bg: Color(hex: "FFF4E6"),
                        fg: Color(hex: "FFB800")
                    )
                    
                    InsightPill(
                        title: "Tips",
                        value: "\(max(viewModel.tips.count, 0))",
                        icon: "lightbulb.fill",
                        bg: Color(hex: "F0E8FF"),
                        fg: Color(hex: "9B6BFF")
                    )
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Daily Tip
    // ─────────────────────────────────────────────
    private func tipSection(_ tip: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Today's Tip", action: nil)
            
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "FFF4E6"))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "FFB800"))
                }
                
                Text(tip)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "444444"))
                    .lineSpacing(4)
                    .lineLimit(3)
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 20)
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - More Tips Carousel
    // ─────────────────────────────────────────────
    private var moreTipsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Expert Tips", action: nil)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.tips.dropFirst().enumerated()), id: \.offset) { idx, tip in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("\(idx + 2)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color(hex: "FF6B9D").opacity(0.8))
                                    .clipShape(Circle())
                                Spacer()
                            }
                            
                            Text(tip)
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "444444"))
                                .lineSpacing(3)
                                .lineLimit(4)
                        }
                        .padding(16)
                        .frame(width: 220, alignment: .topLeading)
                        .background(Color.white)
                        .cornerRadius(18)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Shimmer Loading
    // ─────────────────────────────────────────────
    private var shimmerView: some View {
        VStack(spacing: 28) {
            // Summary shimmer
            ShimmerRect(width: .infinity, height: 50)
                .padding(.horizontal, 20)
            
            // Routine cards shimmer
            VStack(alignment: .leading, spacing: 14) {
                ShimmerRect(width: 120, height: 20)
                    .padding(.horizontal, 20)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            ShimmerRect(width: 155, height: 220)
                                .cornerRadius(24)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            // Products shimmer
            VStack(alignment: .leading, spacing: 14) {
                ShimmerRect(width: 160, height: 20)
                    .padding(.horizontal, 20)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(spacing: 8) {
                                ShimmerRect(width: 140, height: 140)
                                    .cornerRadius(20)
                                ShimmerRect(width: 100, height: 12)
                                ShimmerRect(width: 80, height: 12)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            // Insights shimmer
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShimmerRect(width: 90, height: 120)
                            .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // ─────────────────────────────────────────────
    // Helper functions
    // ─────────────────────────────────────────────
    private func loadCheckins() {
        guard let userId = SessionManager.shared.userId else { return }
        Task {
            do {
                let response = try await APIService.shared.getTodayCheckins(userId: userId)
                await MainActor.run {
                    completedSteps = Set(response.checkins)
                    streaks = (response.streaks.morning, response.streaks.evening)
                }
            } catch {
                #if DEBUG
                print("❌ Failed to load check-ins: \(error)")
                #endif
            }
        }
    }
    
    private func isRoutineComplete(_ type: RoutineType) -> Bool {
        let steps: [FeedRoutineStep]
        switch type {
        case .morning: steps = viewModel.morningSteps
        case .evening: steps = viewModel.eveningSteps
        case .weekly: steps = viewModel.weeklySteps
        }
        guard !steps.isEmpty else { return false }
        let routineTypeStr: String
        switch type {
        case .morning: routineTypeStr = "morning"
        case .evening: routineTypeStr = "evening"
        case .weekly: routineTypeStr = "weekly"
        }
        return steps.allSatisfy { step in
            let key = "\(routineTypeStr):\(step.id)"
            return completedSteps.contains(key)
        }
    }

    private func routineSteps(for type: RoutineType) -> [FeedRoutineStep] {
        switch type {
        case .morning: return viewModel.morningSteps
        case .evening: return viewModel.eveningSteps
        case .weekly: return viewModel.weeklySteps
        }
    }
    
    private func cartProductIds() -> Set<String> {
        Set(cartManager.items.map { $0.product.id })
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Shimmer Effect
// ═══════════════════════════════════════════════════

struct ShimmerRect: View {
    var width: CGFloat
    var height: CGFloat
    @State private var shimmerOffset: CGFloat = -1
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(hex: "F0F0F0"))
            .frame(width: width == .infinity ? nil : width, height: height)
            .frame(maxWidth: width == .infinity ? .infinity : nil)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.4),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset * 200)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 2
                }
            }
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Sub-Components
// ═══════════════════════════════════════════════════

// MARK: Section Header
struct SectionHeader: View {
    let title: String
    var action: String? = "View all"
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2D2D2D"))
            
            Spacer()
            
            if let action = action {
                Button(action) { }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "888888"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "F5F5F5"))
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: Routine Tall Card
struct RoutineTallCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let accent: Color
    var isComplete: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(isComplete ? accent.opacity(0.4) : Color.clear, lineWidth: 2)
                )
            
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 50))
                        .foregroundColor(accent.opacity(0.10))
                        .padding(18)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .lineLimit(2)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12))
                    .cornerRadius(8)
            }
            .padding(18)
        }
        .frame(width: 155, height: 220)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

// MARK: Product Square Card
struct ProductSquareCard: View {
    let product: InferenceProduct
    var isInCart: Bool = false
    let action: () -> Void
    let onAddToCart: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                    
                    if let url = product.image_url {
                        ProductImageView(urlString: url, size: 140)
                            .frame(width: 120, height: 120)
                            .cornerRadius(16)
                            .padding(10)
                    } else {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 36))
                            .foregroundColor(Color(hex: "FFB4C8"))
                            .frame(width: 140, height: 140)
                    }
                    
                    Button(action: onAddToCart) {
                        Image(systemName: isInCart ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(isInCart ? Color(hex: "4ECDC4") : Color(hex: "FF6B9D"))
                            .clipShape(Circle())
                            .shadow(color: Color(hex: "FF6B9D").opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(8)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.brand)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                        .lineLimit(1)
                    
                    Text(product.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "2D2D2D"))
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text("$\(product.price.roundedUpPrice)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        
                        if let rating = product.rating, rating > 0 {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "FFB800"))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "999999"))
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(width: 140)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: Insight Pill
struct InsightPill: View {
    let title: String
    let value: String
    let icon: String
    let bg: Color
    let fg: Color
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(fg.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(fg)
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "2D2D2D"))
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "888888"))
        }
        .frame(width: 90, height: 120)
        .background(bg)
        .cornerRadius(20)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Shared / Reused Components
// ═══════════════════════════════════════════════════

struct ProductImageView: View {
    let urlString: String?
    let size: CGFloat
    
    var body: some View {
        if let urlString = urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity.animation(.easeInOut))
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }
    
    var placeholder: some View {
        ZStack {
            Color(hex: "FFF0F5")
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.25))
                .foregroundColor(Color(hex: "FFB4C8"))
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: Pink drape background
struct PinkDrapeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "FFF0F5"),
                    Color(hex: "FFF5F8"),
                    Color(hex: "FFFAFB"),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            Circle()
                .fill(Color(hex: "FF6B9D").opacity(0.06))
                .frame(width: 420, height: 420)
                .offset(x: -120, y: -180)
                .blur(radius: 40)
            
            Circle()
                .fill(Color(hex: "FFB4C8").opacity(0.08))
                .frame(width: 360, height: 360)
                .offset(x: 160, y: -220)
                .blur(radius: 40)
        }
    }
}

// MARK: Product detail sheet
struct ProductDetailSheet: View {
    let product: InferenceProduct
    @ObservedObject var cartManager: CartManager
    let fit: APIService.CartAnalysisItem?
    let showFullFit: Bool
    @Environment(\.dismiss) private var dismiss
    
    var isInCart: Bool {
        cartManager.contains(productId: product.id)
    }

    private var fitBadgeColor: Color {
        switch fit?.label {
        case "Great fit": return Color(hex: "4ECDC4")
        case "Good match": return Color(hex: "FFB800")
        case "Caution": return Color(hex: "FF6B6B")
        default: return Color(hex: "C0C0C0")
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
                            .frame(height: 320)
                        
                        ProductImageView(urlString: product.image_url, size: 300)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 280)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text(product.brand)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                        
                        Text(product.name)
                            .font(.custom("Didot", size: 28))
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "2D2D2D"))
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack {
                            Text("$\(product.price.roundedUpPrice)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Color(hex: "2D2D2D"))
                            
                            Spacer()
                            
                            if let rating = product.rating {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "FFB800"))
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color(hex: "666666"))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(hex: "FFF9EE"))
                                .cornerRadius(12)
                            }
                        }
                        
                        Text(product.category)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "888888"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "F5F5F5"))
                            .cornerRadius(10)
                        
                        if let description = product.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 15))
                                .foregroundColor(Color(hex: "666666"))
                                .lineSpacing(5)
                                .padding(.top, 6)
                        }

                        if let fit = fit {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Fit for your skin")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(hex: "2D2D2D"))

                                HStack(alignment: .top, spacing: 8) {
                                    Text(fit.label)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(fitBadgeColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(fitBadgeColor.opacity(0.12))
                                        .cornerRadius(10)
                                    Text(fit.reason)
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(hex: "666666"))
                                        .lineLimit(showFullFit ? nil : 2)
                                        .fixedSize(horizontal: false, vertical: showFullFit)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 120)
                }
            }
            .background(PinkDrapeBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                            .padding(10)
                            .background(Color.white.opacity(0.95))
                            .clipShape(Circle())
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    cartManager.addToCart(product)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: isInCart ? "checkmark.circle.fill" : "bag.fill.badge.plus")
                            .font(.system(size: 18, weight: .bold))
                        Text(isInCart ? "Add one more — $\(product.price.roundedUpPrice)" : "Add to Cart — $\(product.price.roundedUpPrice)")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: isInCart ? [Color(hex: "4ECDC4"), Color(hex: "6BD9D1")] : [Color(hex: "FF6B9D"), Color(hex: "FFB4C8")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: (isInCart ? Color(hex: "4ECDC4") : Color(hex: "FF6B9D")).opacity(0.3), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.0), Color.white.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .frame(height: 140)
                )
            }
        }
    }
}

// MARK: Quick buy sheet
struct QuickBuySheet: View {
    @ObservedObject var cartManager: CartManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var paymentHandler = PaymentHandler()
    @State private var analysis: [String: APIService.CartAnalysisItem] = [:]
    @State private var isAgentBuying = false
    @State private var orderPlaced = false
    @State private var showAddressAlert = false
    @State private var showingProductDetail: InferenceProduct?
    @State private var selectedFit: APIService.CartAnalysisItem?
    @State private var isLoadingAnalysis = false
    
    private var userId: String? { SessionManager.shared.userId }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "FFF5F8").ignoresSafeArea()
                
                if orderPlaced {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundColor(Color(hex: "4ECDC4"))
                        Text("Order placed")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        Text("Your glow-up is on the way ✨")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "999999"))
                    }
                } else if isAgentBuying {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Color(hex: "FF6B9D"))
                        Text("Purchasing…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "888888"))
                    }
                } else {
                    VStack(spacing: 0) {
                        // Subtitle
                        Text("Our agents find the best products at the best price for you.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "B0B0B0"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        
                        if cartManager.items.isEmpty {
                            Spacer()
                            VStack(spacing: 10) {
                                Image(systemName: "bag")
                                    .font(.system(size: 32, weight: .thin))
                                    .foregroundColor(Color(hex: "D4A0B0"))
                                Text("Cart is empty")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color(hex: "999999"))
                            }
                            Spacer()
                        } else if isLoadingAnalysis {
                            Spacer()
                            VStack(spacing: 10) {
                                ProgressView()
                                    .tint(Color(hex: "FF6B9D"))
                                Text("Personalizing your fit…")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(hex: "999999"))
                            }
                            Spacer()
                        } else {
                            // Product list
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 10) {
                                    ForEach(cartManager.items) { item in
                                        let pid = item.product.id
                                        QuickBuyRow(
                                            item: item,
                                            quantity: cartManager.quantity(for: pid),
                                            analysis: analysis[pid],
                                            onOpen: {
                                                showingProductDetail = item.product
                                                selectedFit = analysis[pid]
                                            },
                                            onIncrement: {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    cartManager.incrementLocal(productId: pid)
                                                }
                                            },
                                            onDecrement: {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    cartManager.decrementLocal(productId: pid)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                            }
                            
                            // Bottom bar
                            VStack(spacing: 10) {
                                Divider()
                                
                                HStack {
                                    Text("Total")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(Color(hex: "888888"))
                                    Spacer()
                                    Text("$\(String(format: "%.2f", cartManager.checkoutTotal))")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(Color(hex: "2D2D2D"))
                                }
                                .padding(.horizontal, 20)
                                
                                HStack {
                                    Text("Includes GlowUp markup")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "AAAAAA"))
                                    Spacer()
                                    Text("+$\(String(format: "%.2f", cartManager.markupTotal))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Color(hex: "AAAAAA"))
                                }
                                .padding(.horizontal, 20)
                                
                                VStack(spacing: 6) {
                                    ApplePayButton()
                                        .frame(height: 48)
                                        .onTapGesture { startApplePay() }
                                    Text("Pay securely with Apple Pay")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(Color(hex: "AAAAAA"))
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                            }
                            .background(Color(hex: "FFF5F8"))
                        }
                    }
                }
            }
            .navigationTitle("Quick Buy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        cartManager.flushPendingChanges()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "FF6B9D"))
                }
            }
        }
        .onAppear { loadAnalysis() }
        .onDisappear { cartManager.flushPendingChanges() }
        .alert("Add a shipping address", isPresented: $showAddressAlert) {
            Button("Go to Settings") { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your address isn't set yet. Please add it in Settings → Shipping.")
        }
        .sheet(item: $showingProductDetail) { product in
            ProductDetailSheet(product: product, cartManager: cartManager, fit: selectedFit, showFullFit: true)
        }
    }
    
    private func loadAnalysis() {
        guard let userId = userId else { return }
        let productIds = cartManager.items.map { $0.product.id }
        guard !productIds.isEmpty else { return }
        isLoadingAnalysis = true
        Task {
            do {
                let items = try await APIService.shared.analyzeCart(userId: userId, productIds: productIds)
                await MainActor.run {
                    analysis = Dictionary(uniqueKeysWithValues: items.map { ($0.product_id, $0) })
                    isLoadingAnalysis = false
                }
            } catch {
                #if DEBUG
                print("❌ Failed to analyze cart: \(error)")
                #endif
                await MainActor.run { isLoadingAnalysis = false }
            }
        }
    }
    
    private func startApplePay() {
        // Flush local qty changes before paying
        cartManager.flushPendingChanges()
        
        guard SessionManager.shared.hasShippingAddress else {
            showAddressAlert = true
            return
        }
        let purchasedItems = cartManager.items
        paymentHandler.startPayment(items: purchasedItems, total: cartManager.checkoutTotal) { success in
            if success {
                withAnimation { isAgentBuying = true }
                Task {
                    let uid = userId ?? "guest"
                    let _ = try? await APIService.shared.createOrder(userId: uid, items: purchasedItems)
                    
                    // Integrate each purchased product into the user's routine
                    for item in purchasedItems {
                        try? await APIService.shared.integrateProductIntoRoutine(userId: uid, productId: item.product.id)
                    }
                    
                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            isAgentBuying = false
                            orderPlaced = true
                        }
                        cartManager.clearCart()
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────
// MARK: - Quick Buy Row
// ─────────────────────────────────────────────────

struct QuickBuyRow: View {
    let item: CartItem
    let quantity: Int
    let analysis: APIService.CartAnalysisItem?
    let onOpen: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    
    private var badgeColor: Color {
        switch analysis?.label {
        case "Great fit": return Color(hex: "4ECDC4")
        case "Good match": return Color(hex: "FFB800")
        case "Caution": return Color(hex: "FF6B6B")
        default: return Color(hex: "C0C0C0")
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Image
            Button(action: onOpen) {
                ProductImageView(urlString: item.product.image_url, size: 64)
                    .frame(width: 64, height: 64)
                    .background(Color(hex: "FFF0F5"))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.brand.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "D4879C"))
                    .tracking(0.3)
                
                Button(action: onOpen) {
                    Text(item.product.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                
                if let a = analysis {
                    HStack(spacing: 4) {
                        Text(a.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.12))
                            .cornerRadius(6)
                        Text(a.reason)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "999999"))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            // Price + stepper
            VStack(spacing: 6) {
                Text("$\(item.product.price.roundedUpPriceWithMarkup)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                // Compact stepper
                HStack(spacing: 0) {
                    Button(action: onDecrement) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "666666"))
                            .frame(width: 26, height: 26)
                            .background(Color(hex: "F0F0F0"))
                            .cornerRadius(6, corners: [.topLeft, .bottomLeft])
                    }
                    
                    Text("\(quantity)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "2D2D2D"))
                        .frame(width: 26, height: 26)
                        .background(Color.white)
                    
                    Button(action: onIncrement) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Color(hex: "FF6B9D"))
                            .cornerRadius(6, corners: [.topRight, .bottomRight])
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "E8E8E8"), lineWidth: 0.5)
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "F0E0E8"), lineWidth: 0.5)
        )
    }
}

// MARK: Routine detail sheet
struct RoutineDetailSheet: View {
    let routineType: HomeView.RoutineType
    let steps: [FeedRoutineStep]
    let morningSteps: [FeedRoutineStep]
    let eveningSteps: [FeedRoutineStep]
    let weeklySteps: [FeedRoutineStep]
    @Binding var completedSteps: Set<String>
    @Binding var streaks: (morning: Int, evening: Int)
    let userId: String
    let onRoutineUpdated: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var isEditing = false
    @State private var isSavingRoutine = false
    @State private var saveError: String?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var isPreparingShare = false
    @State private var shareError: String?
    @State private var editableSteps: [EditableRoutineStep] = []
    @State private var showingStepEditor = false
    @State private var editingStepLocalId: String?
    @State private var editorDraft = EditableRoutineStep.blank(step: 1, frequency: "daily")
    
    private var routineTypeStr: String {
        switch routineType {
        case .morning: return "morning"
        case .evening: return "evening"
        case .weekly: return "weekly"
        }
    }
    
    private var title: String {
        switch routineType {
        case .morning: return "Morning Glow"
        case .evening: return "Evening Repair"
        case .weekly: return "Weekly Reset"
        }
    }
    
    private var icon: String {
        switch routineType {
        case .morning: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        case .weekly: return "sparkles"
        }
    }
    
    private var accentColor: Color {
        switch routineType {
        case .morning: return Color(hex: "FF6B9D")
        case .evening: return Color(hex: "9B6BFF")
        case .weekly: return Color(hex: "4ECDC4")
        }
    }
    
    private var currentStreak: Int {
        switch routineType {
        case .morning: return streaks.morning
        case .evening: return streaks.evening
        case .weekly: return 0
        }
    }

    private var defaultFrequency: String {
        routineType == .weekly ? "weekly" : "daily"
    }

    private var frequencyOptions: [String] {
        routineType == .weekly ? ["weekly"] : ["daily", "weekly"]
    }

    private var orderedEditableSteps: [EditableRoutineStep] {
        editableSteps.sorted { $0.step < $1.step }
    }
    
    private var isComplete: Bool {
        let activeSteps = orderedEditableSteps.map { $0.asFeedStep }
        guard !activeSteps.isEmpty else { return false }
        return activeSteps.allSatisfy { step in
            let key = "\(routineTypeStr):\(step.id)"
            return completedSteps.contains(key)
        }
    }

    private var shareText: String {
        let lines = orderedEditableSteps.map { step -> String in
            var out = "\(step.step). \(step.name)"
            if let productName = step.productName, !productName.isEmpty {
                out += " - \(productName)"
            }
            if let brand = step.productBrand, !brand.isEmpty {
                out += " (\(brand))"
            }
            if let productId = step.productId, !productId.isEmpty {
                out += "\n   Product ID: \(productId)"
            }
            if !step.instructions.isEmpty {
                out += "\n   \(step.instructions)"
            }
            return out
        }
        return "\(title)\n\n" + lines.joined(separator: "\n\n")
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 50))
                            .foregroundColor(accentColor)
                        
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        
                        if routineType != .weekly && currentStreak > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "FF6B00"))
                                Text("\(currentStreak) day streak")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "FF6B00"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "FFF4E6"))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.top, 20)

                    if isEditing {
                        Text("Edit mode: choose specific products, adjust steps, then save.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "777777"))
                            .padding(.horizontal, 20)
                    }
                    
                    VStack(spacing: 16) {
                        ForEach(orderedEditableSteps) { editableStep in
                            let step = editableStep.asFeedStep
                            RoutineStepRow(
                                step: step,
                                isCompleted: completedSteps.contains("\(routineTypeStr):\(step.id)"),
                                accentColor: accentColor,
                                onToggle: { toggleStep(step) },
                                onEdit: isEditing ? { beginEditing(step: editableStep) } : nil,
                                onDelete: isEditing ? { deleteStep(step: editableStep) } : nil
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    if isEditing {
                        VStack(spacing: 12) {
                            Button(action: addStep) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Step")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(accentColor.opacity(0.12))
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: saveRoutineEdits) {
                                HStack(spacing: 8) {
                                    if isSavingRoutine {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                    Text(isSavingRoutine ? "Saving..." : "Save Routine")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(accentColor)
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isSavingRoutine || orderedEditableSteps.isEmpty)

                            if let saveError {
                                Text(saveError)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "D64545"))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    if isComplete {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(accentColor)
                            Text("Routine Complete! ✨")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(hex: "2D2D2D"))
                            Text("Keep up the great work!")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "888888"))
                        }
                        .padding(.vertical, 20)
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .background(PinkDrapeBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                resetEditableSteps()
            }
            .sheet(isPresented: $showingStepEditor) {
                RoutineStepEditorSheet(
                    draft: $editorDraft,
                    userId: userId,
                    frequencyOptions: frequencyOptions,
                    onSave: applyEditorDraft
                )
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityShareSheet(items: shareItems)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: prepareShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isPreparingShare ? Color(hex: "AAAAAA") : Color(hex: "666666"))
                    }
                    .disabled(isPreparingShare)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if isEditing {
                            resetEditableSteps()
                            saveError = nil
                        }
                        isEditing.toggle()
                    }) {
                        Text(isEditing ? "Cancel" : "Edit")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "888888"))
                            .frame(width: 30, height: 30)
                            .background(Color(hex: "F5F5F5"))
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    private func resetEditableSteps() {
        editableSteps = steps
            .sorted { $0.step < $1.step }
            .map(EditableRoutineStep.init(feedStep:))
    }

    private func beginEditing(step: EditableRoutineStep) {
        editingStepLocalId = step.localId
        editorDraft = step
        showingStepEditor = true
    }

    private func addStep() {
        let nextStep = max(orderedEditableSteps.count + 1, 1)
        editingStepLocalId = nil
        editorDraft = .blank(step: nextStep, frequency: defaultFrequency)
        showingStepEditor = true
    }

    private func deleteStep(step: EditableRoutineStep) {
        editableSteps.removeAll { $0.localId == step.localId }
        normalizeStepOrdering()
    }

    private func applyEditorDraft() {
        if let localId = editingStepLocalId, let idx = editableSteps.firstIndex(where: { $0.localId == localId }) {
            editableSteps[idx] = editorDraft
        } else {
            editableSteps.append(editorDraft)
        }
        editingStepLocalId = nil
        normalizeStepOrdering()
    }

    private func normalizeStepOrdering() {
        let sorted = editableSteps.sorted { $0.step < $1.step }
        editableSteps = sorted.enumerated().map { index, item in
            var copy = item
            copy.step = index + 1
            if copy.frequency.isEmpty { copy.frequency = defaultFrequency }
            return copy
        }
    }

    private func saveRoutineEdits() {
        guard !userId.isEmpty else { return }
        guard !orderedEditableSteps.isEmpty else { return }
        isSavingRoutine = true
        saveError = nil

        let edited = orderedEditableSteps.map { $0.asUpdateStep }
        let morningPayload = routineType == .morning
            ? edited
            : routinePayloadSteps(from: morningSteps, frequency: "daily")
        let eveningPayload = routineType == .evening
            ? edited
            : routinePayloadSteps(from: eveningSteps, frequency: "daily")
        let weeklyPayload = routineType == .weekly
            ? edited
            : routinePayloadSteps(from: weeklySteps, frequency: "weekly")

        Task {
            do {
                try await APIService.shared.updateRoutine(
                    userId: userId,
                    morning: morningPayload,
                    evening: eveningPayload,
                    weekly: weeklyPayload,
                    summary: "Routine updated from app"
                )
                _ = await NotificationManager.shared.syncScheduledNotifications(userId: userId)
                let response = try await APIService.shared.getTodayCheckins(userId: userId)
                await MainActor.run {
                    completedSteps = Set(response.checkins)
                    streaks = (response.streaks.morning, response.streaks.evening)
                    isSavingRoutine = false
                    isEditing = false
                    onRoutineUpdated?()
                }
            } catch {
                await MainActor.run {
                    isSavingRoutine = false
                    saveError = "Couldn't save right now. Please try again."
                }
            }
        }
    }

    private func routinePayloadSteps(from feedSteps: [FeedRoutineStep], frequency: String) -> [APIService.RoutineUpdateStep] {
        feedSteps.map { step in
            APIService.RoutineUpdateStep(
                step: step.step,
                name: step.name,
                instructions: step.tip ?? "",
                frequency: frequency,
                product_id: step.product_id,
                product_name: step.product_name
            )
        }
    }
    
    private func toggleStep(_ step: FeedRoutineStep) {
        let key = "\(routineTypeStr):\(step.id)"
        let isCurrentlyCompleted = completedSteps.contains(key)
        
        isLoading = true
        Task {
            do {
                if isCurrentlyCompleted {
                    _ = try await APIService.shared.markStepIncomplete(
                        userId: userId,
                        routineType: routineTypeStr,
                        stepId: step.id
                    )
                } else {
                    _ = try await APIService.shared.markStepComplete(
                        userId: userId,
                        routineType: routineTypeStr,
                        stepId: step.id,
                        stepName: step.name
                    )
                }
                
                let response = try await APIService.shared.getTodayCheckins(userId: userId)
                await MainActor.run {
                    completedSteps = Set(response.checkins)
                    streaks = (response.streaks.morning, response.streaks.evening)
                    isLoading = false
                }
            } catch {
                #if DEBUG
                print("❌ Failed to toggle step: \(error)")
                #endif
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func prepareShare() {
        guard !userId.isEmpty else { return }
        isPreparingShare = true
        shareError = nil
        Task {
            do {
                let response = try await APIService.shared.createRoutineShareLink(userId: userId, routineType: routineTypeStr)
                let url = URL(string: response.share_url)
                let fallback = "\(title)\n\n\(shareText)"
                await MainActor.run {
                    var items: [Any] = [fallback]
                    if let url { items.insert(url, at: 0) }
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

struct EditableRoutineStep: Identifiable {
    let localId: String
    var step: Int
    var name: String
    var instructions: String
    var frequency: String
    var productId: String?
    var productName: String?
    var productBrand: String?
    var productPrice: Double?
    var productImage: String?
    var buyLink: String?

    var id: String { localId }

    init(
        localId: String = UUID().uuidString,
        step: Int,
        name: String,
        instructions: String,
        frequency: String,
        productId: String? = nil,
        productName: String? = nil,
        productBrand: String? = nil,
        productPrice: Double? = nil,
        productImage: String? = nil,
        buyLink: String? = nil
    ) {
        self.localId = localId
        self.step = step
        self.name = name
        self.instructions = instructions
        self.frequency = frequency
        self.productId = productId
        self.productName = productName
        self.productBrand = productBrand
        self.productPrice = productPrice
        self.productImage = productImage
        self.buyLink = buyLink
    }

    init(feedStep: FeedRoutineStep) {
        self.localId = UUID().uuidString
        self.step = feedStep.step
        self.name = feedStep.name
        self.instructions = feedStep.tip ?? ""
        self.frequency = "daily"
        self.productId = feedStep.product_id
        self.productName = feedStep.product_name
        self.productBrand = feedStep.product_brand
        self.productPrice = feedStep.product_price
        self.productImage = feedStep.product_image
        self.buyLink = feedStep.buy_link
    }

    static func blank(step: Int, frequency: String) -> EditableRoutineStep {
        EditableRoutineStep(
            step: step,
            name: "",
            instructions: "",
            frequency: frequency
        )
    }

    var asFeedStep: FeedRoutineStep {
        FeedRoutineStep(
            step: step,
            name: name,
            tip: instructions,
            product_id: productId,
            product_name: productName,
            product_brand: productBrand,
            product_price: productPrice,
            product_image: productImage,
            buy_link: buyLink
        )
    }

    var asUpdateStep: APIService.RoutineUpdateStep {
        APIService.RoutineUpdateStep(
            step: step,
            name: name.isEmpty ? "Step \(step)" : name,
            instructions: instructions,
            frequency: frequency.isEmpty ? "daily" : frequency,
            product_id: productId,
            product_name: productName
        )
    }
}

struct RoutineStepEditorSheet: View {
    @Binding var draft: EditableRoutineStep
    let userId: String
    let frequencyOptions: [String]
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var searchResults: [FeedProduct] = []
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Stepper(value: $draft.step, in: 1...12) {
                        Text("Step \(draft.step)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                    }

                    TextField("Step title (e.g. Brightening Serum)", text: $draft.name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Instructions", text: $draft.instructions, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)

                    Picker("Frequency", selection: $draft.frequency) {
                        ForEach(frequencyOptions, id: \.self) { opt in
                            Text(opt.capitalized).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attach Product")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "2D2D2D"))

                        HStack(spacing: 8) {
                            TextField("Search product name or concern", text: $searchQuery)
                                .textFieldStyle(.roundedBorder)

                            Button(action: runSearch) {
                                if isSearching {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Search")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color(hex: "FF6B9D"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .disabled(isSearching || searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let productName = draft.productName, !productName.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(productName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "2D2D2D"))
                                HStack(spacing: 6) {
                                    if let brand = draft.productBrand, !brand.isEmpty {
                                        Text(brand)
                                    }
                                    if let price = draft.productPrice {
                                        Text(String(format: "$%.2f", price))
                                    }
                                }
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "777777"))
                                if let productId = draft.productId, !productId.isEmpty {
                                    Text("ID: \(productId)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color(hex: "999999"))
                                }
                                Button("Remove Product") {
                                    draft.productId = nil
                                    draft.productName = nil
                                    draft.productBrand = nil
                                    draft.productPrice = nil
                                    draft.productImage = nil
                                    draft.buyLink = nil
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "D64545"))
                            }
                            .padding(10)
                            .background(Color(hex: "FFF8FA"))
                            .cornerRadius(10)
                        }

                        if let searchError {
                            Text(searchError)
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "D64545"))
                        }

                        VStack(spacing: 8) {
                            ForEach(searchResults) { product in
                                Button(action: { selectProduct(product) }) {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(product.name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(Color(hex: "2D2D2D"))
                                                .multilineTextAlignment(.leading)
                                            Text("\(product.brand) • \(String(format: "$%.2f", product.price))")
                                                .font(.system(size: 12))
                                                .foregroundColor(Color(hex: "666666"))
                                            Text("ID: \(product.id)")
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundColor(Color(hex: "999999"))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(Color.white)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color(hex: "F0E0E8"), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(hex: "FFF5F8").ignoresSafeArea())
            .navigationTitle("Edit Routine Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.name = draft.productName ?? "Step \(draft.step)"
                        }
                        if draft.frequency.isEmpty {
                            draft.frequency = "daily"
                        }
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }

    private func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil

        Task {
            do {
                let products = try await APIService.shared.searchRoutineProducts(
                    userId: userId.isEmpty ? nil : userId,
                    query: query,
                    limit: 8
                )
                await MainActor.run {
                    searchResults = products
                    isSearching = false
                    if products.isEmpty {
                        searchError = "No products found. Try another keyword."
                    }
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    searchError = "Search failed. Please try again."
                }
            }
        }
    }

    private func selectProduct(_ product: FeedProduct) {
        draft.productId = product.id
        draft.productName = product.name
        draft.productBrand = product.brand
        draft.productPrice = product.price
        draft.productImage = product.image_url
        draft.buyLink = product.buy_link
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = product.category.capitalized
        }
    }
}

struct RoutineStepRow: View {
    let step: FeedRoutineStep
    let isCompleted: Bool
    let accentColor: Color
    let onToggle: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? accentColor : Color.white)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(isCompleted ? accentColor : Color(hex: "E0E0E0"), lineWidth: 2)
                        )
                    
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Step \(step.step)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.12))
                        .cornerRadius(6)
                    
                    Spacer()

                    if let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(accentColor)
                                .padding(6)
                                .background(accentColor.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "D64545"))
                                .padding(6)
                                .background(Color(hex: "FFEDEE"))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Text(step.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .strikethrough(isCompleted)
                    .opacity(isCompleted ? 0.6 : 1.0)
                
                // Show product info when available
                if step.hasProduct || !(step.product_name ?? "").isEmpty {
                    HStack(spacing: 10) {
                        if let imgUrl = step.product_image, let url = URL(string: imgUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: "F5F0F0"))
                                    .overlay(
                                        Image(systemName: "drop.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(hex: "FFADC6"))
                                    )
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.product_name ?? "")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "444444"))
                                .lineLimit(2)
                            
                            HStack(spacing: 6) {
                                if let brand = step.product_brand {
                                    Text(brand)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(Color(hex: "999999"))
                                }
                                if let price = step.product_price, price > 0 {
                                    Text("$\(Int(price.rounded(.up)))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(accentColor)
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
                    }
                    .padding(10)
                    .background(Color(hex: "FFF8FA"))
                    .cornerRadius(10)
                }
                
                if let tip = step.tip, !tip.isEmpty {
                    Text(tip)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "666666"))
                        .lineSpacing(4)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(isCompleted ? accentColor.opacity(0.08) : Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCompleted ? accentColor.opacity(0.3) : Color(hex: "F0F0F0"), lineWidth: 1)
        )
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HomeView(
        cartManager: CartManager()
    )
}
