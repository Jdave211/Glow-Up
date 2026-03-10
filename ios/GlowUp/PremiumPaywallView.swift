import SwiftUI

private let privacyPolicyURL = URL(string: "https://boiled-education-5d3.notion.site/GlowUp-Privacy-Policy-867796a49e504c3d839ce15de6ade6f3?source=copy_link")!
private let termsOfServiceURL = URL(string: "https://boiled-education-5d3.notion.site/GlowUp-Terms-of-Service-a17b8e90751743dba5a33e2a03dd4b64?source=copy_link")!
private let supportURL = URL(string: "https://boiled-education-5d3.notion.site/GlowUp-Support-b4226f97acba41e3bd4803fa1d0624fb?source=copy_link")!

private struct PaywallFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

private let premiumFeatures: [PaywallFeature] = [
    .init(icon: "sparkles", title: "Unlimited Analysis", subtitle: "Detailed reports anytime"),
    .init(icon: "checkmark.circle.fill", title: "Personalized Routine", subtitle: "Daily steps for you"),
    .init(icon: "star.fill", title: "Product Matches", subtitle: "Curated for your skin"),
    .init(icon: "chart.line.uptrend.xyaxis", title: "Progress Tracking", subtitle: "See improvement")
]

private extension SubscriptionManager.Plan {
    var marketingName: String {
        switch self {
        case .weekly: return "GlowUp+ Weekly"
        case .monthly: return "GlowUp+ Monthly"
        }
    }

    var durationLabel: String {
        switch self {
        case .weekly: return "1 week"
        case .monthly: return "1 month"
        }
    }
}

private struct SubscriptionDisclosureBlock: View {
    let plan: SubscriptionManager.Plan
    let price: String
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(plan.marketingName): \(price) for \(plan.durationLabel).")
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundColor(Color(hex: "4B5563"))
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text("Auto-renews unless canceled at least 24 hours before the current period ends. Manage subscriptions in your App Store account settings.")
                .font(.system(size: compact ? 10 : 11))
                .foregroundColor(Color(hex: "6B7280"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 10 : 12)
        .background(Color(hex: "F8FAFC"))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
    }
}

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    let isDismissible: Bool
    let onUpgradeSuccess: (() -> Void)?
    
    @State private var selectedPlan: SubscriptionManager.Plan = .monthly
    @State private var skinTone: Double?

    init(
        isDismissible: Bool = true,
        onUpgradeSuccess: (() -> Void)? = nil
    ) {
        self.isDismissible = isDismissible
        self.onUpgradeSuccess = onUpgradeSuccess
    }
    
    private var ctaTitle: String {
        if subscriptionManager.purchaseInProgress || subscriptionManager.isLoadingProducts {
            return "Processing..."
        }
        let price = subscriptionManager.displayPrice(for: selectedPlan)
        return "Continue • \(price)/\(selectedPlan.periodLabel)"
    }
    
    private var backgroundImageName: String {
        // If skinTone is missing, default to "everyone" (darker/inclusive)
        // If skinTone < 0.4 (Fair/Light), use "whitwe"
        // Else use "everyone"
        guard let tone = skinTone else { return "everyone" }
        return tone < 0.4 ? "whitwe" : "everyone"
    }
    
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760
            let heroHeight = min(
                max(proxy.size.height * (compact ? 0.33 : 0.37), compact ? 200 : 220),
                compact ? 250 : 320
            )
            let sheetHorizontalPadding: CGFloat = compact ? 12 : 14
            let contentHorizontalPadding: CGFloat = compact ? 16 : 20
            let sheetVerticalPadding: CGFloat = compact ? 14 : 20
            let sheetBottomPadding = max(compact ? 10 : 14, proxy.safeAreaInsets.bottom + (compact ? 8 : 14))

            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(hex: "FFE8F2"), Color(hex: "FFF8FB")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    heroSection(height: heroHeight, compact: compact)

                    VStack(spacing: compact ? 10 : 14) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: compact ? 10 : 12) {
                            ForEach(premiumFeatures) { feature in
                                HStack(alignment: .top, spacing: compact ? 8 : 10) {
                                    Image(systemName: feature.icon)
                                        .font(.system(size: compact ? 12 : 14, weight: .semibold))
                                        .foregroundColor(Color(hex: "FF5C95"))
                                        .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                                        .background(Color(hex: "FFF0F5"))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                                        Text(feature.title)
                                            .font(.system(size: compact ? 12 : 14, weight: .bold))
                                            .foregroundColor(Color(hex: "1A1D2B"))
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.82)
                                        Text(feature.subtitle)
                                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                                            .foregroundColor(Color(hex: "8A92A6"))
                                            .lineLimit(compact ? 1 : 2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(compact ? 8 : 10)
                                .frame(maxWidth: .infinity, minHeight: compact ? 62 : 74, alignment: .leading)
                                .background(Color(hex: "F9FAFB"))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.top, compact ? 2 : 6)

                        HStack(spacing: compact ? 10 : 12) {
                            ForEach(SubscriptionManager.Plan.allCases) { plan in
                                CompactPlanCard(
                                    plan: plan,
                                    price: subscriptionManager.displayPrice(for: plan),
                                    isSelected: selectedPlan == plan,
                                    compact: compact
                                ) {
                                    withAnimation(.spring()) {
                                        selectedPlan = plan
                                    }
                                }
                            }
                        }

                        if let error = subscriptionManager.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                                .foregroundColor(Color(hex: "BC3F71"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }

                        Button(action: {
                            Task {
                                let success = await subscriptionManager.purchase(plan: selectedPlan)
                                if success {
                                    handleUnlockSuccess()
                                }
                            }
                        }) {
                            ZStack {
                                Text(ctaTitle)
                                    .font(.system(size: compact ? 16 : 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .opacity(subscriptionManager.purchaseInProgress ? 0 : 1)

                                if subscriptionManager.purchaseInProgress {
                                    ProgressView().tint(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, compact ? 13 : 16)
                            .background(Color(hex: "FF5C95"))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(hex: "FF5C95").opacity(0.35), radius: 9, x: 0, y: 4)
                        }
                        .disabled(subscriptionManager.purchaseInProgress || subscriptionManager.isLoadingProducts)

                        SubscriptionDisclosureBlock(
                            plan: selectedPlan,
                            price: subscriptionManager.displayPrice(for: selectedPlan),
                            compact: compact
                        )

                        HStack(spacing: compact ? 12 : 16) {
                            Button("Restore") {
                                Task {
                                    await subscriptionManager.restorePurchases()
                                    if subscriptionManager.isPremium {
                                        handleUnlockSuccess()
                                    }
                                }
                            }
                            Button("Terms") { openURL(termsOfServiceURL) }
                            Button("Privacy") { openURL(privacyPolicyURL) }
                            Button("Support") { openURL(supportURL) }
                        }
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundColor(Color(hex: "8A92A6"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.top, sheetVerticalPadding)
                    .padding(.bottom, sheetBottomPadding)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color(hex: "F2E8ED"), lineWidth: 1)
                    )
                    .padding(.horizontal, sheetHorizontalPadding)
                    .padding(.top, compact ? -18 : -26)
                }
                .ignoresSafeArea(edges: .top)

                if isDismissible {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(9)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.top, max(14, proxy.safeAreaInsets.top + 8))
                    .padding(.trailing, 20)
                }
            }
        }
        .onChange(of: subscriptionManager.isPremium) { _, isPremium in
            if isPremium {
                handleUnlockSuccess()
            }
        }
        .interactiveDismissDisabled(!isDismissible)
        .task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.refreshEntitlements()
            if subscriptionManager.isPremium {
                handleUnlockSuccess()
                return
            }
            if let userId = SessionManager.shared.userId {
                if let profile = try? await SupabaseService.shared.getSkinProfile(userId: userId) {
                    self.skinTone = profile.skinTone
                }
            }
        }
    }

    private func handleUnlockSuccess() {
        onUpgradeSuccess?()
        if isDismissible {
            dismiss()
        }
    }

    private func heroSection(height: CGFloat, compact: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(backgroundImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)

            VStack(alignment: .leading, spacing: 8) {
                Text("Unlock GlowUp+")
                    .font(.system(size: compact ? 30 : 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text("Photo analysis, progress tracking, and routines that stay personalized.")
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(compact ? 2 : 3)
            }
            .padding(.horizontal, compact ? 18 : 22)
            .padding(.bottom, compact ? 18 : 30)
        }
    }
}

// MARK: - Components

struct CompactPlanCard: View {
    let plan: SubscriptionManager.Plan
    let price: String
    let isSelected: Bool
    let compact: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 6 : 8) {
                if plan == .monthly {
                    Text("BEST VALUE")
                        .font(.system(size: compact ? 8 : 9, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, compact ? 7 : 8)
                        .padding(.vertical, compact ? 2 : 3)
                        .background(Color(hex: "FF5C95"))
                        .cornerRadius(4)
                } else {
                    Text("FLEXIBLE")
                        .font(.system(size: compact ? 8 : 9, weight: .heavy))
                        .foregroundColor(Color(hex: "8A92A6"))
                        .padding(.horizontal, compact ? 7 : 8)
                        .padding(.vertical, compact ? 2 : 3)
                        .background(Color(hex: "F3F4F6"))
                        .cornerRadius(4)
                }
                
                Text(plan == .weekly ? "Weekly" : "Monthly")
                    .font(.system(size: compact ? 13 : 15, weight: .bold))
                    .foregroundColor(Color(hex: "1A1D2B"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Text(price)
                    .font(.system(size: compact ? 12 : 14, weight: .medium))
                    .foregroundColor(Color(hex: "57607A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 94 : 112, alignment: .center)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 8 : 10)
            .background(isSelected ? Color(hex: "FFF0F5") : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color(hex: "FF5C95") : Color(hex: "E5E7EB"), lineWidth: 2)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// Keep MiniPostOnboardingPaywallView focused on post-onboarding premium gate.
struct MiniPostOnboardingPaywallView: View {
    let onUpgradeSuccess: () -> Void

    @Environment(\.openURL) private var openURL
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedPlan: SubscriptionManager.Plan = .weekly

    private var ctaTitle: String {
        if subscriptionManager.purchaseInProgress || subscriptionManager.isLoadingProducts {
            return "Processing..."
        }
        let price = subscriptionManager.displayPrice(for: selectedPlan)
        return "Unlock now • \(price)/\(selectedPlan.periodLabel)"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FFF8F6"), Color(hex: "FFF0F5")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer(minLength: 8)

                Text("GlowUp Premium")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hex: "1A1D2B"))

                Text("Premium is required to continue after onboarding.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "57607A"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                jamwallCard

                if let error = subscriptionManager.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "BC3F71"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: {
                    Task {
                        let success = await subscriptionManager.purchase(plan: selectedPlan)
                        if success {
                            onUpgradeSuccess()
                        }
                    }
                }) {
                    ZStack {
                        Text(ctaTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(subscriptionManager.purchaseInProgress ? 0 : 1)

                        if subscriptionManager.purchaseInProgress {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "FF5C95"))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color(hex: "FF5C95").opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(subscriptionManager.purchaseInProgress || subscriptionManager.isLoadingProducts)
                .padding(.horizontal, 20)

                SubscriptionDisclosureBlock(
                    plan: selectedPlan,
                    price: subscriptionManager.displayPrice(for: selectedPlan)
                )
                .padding(.horizontal, 20)

                HStack(spacing: 20) {
                    Button("Restore") {
                        Task {
                            await subscriptionManager.restorePurchases()
                            if subscriptionManager.isPremium {
                                onUpgradeSuccess()
                            }
                        }
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "8A92A6"))

                HStack(spacing: 16) {
                    Button("Terms") { openURL(termsOfServiceURL) }
                    Button("Privacy") { openURL(privacyPolicyURL) }
                    Button("Support") { openURL(supportURL) }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "8A92A6"))

                Spacer(minLength: 10)
            }
            .padding(.bottom, 18)
        }
        .task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.refreshEntitlements()
            if subscriptionManager.isPremium {
                onUpgradeSuccess()
            }
        }
    }

    private var jamwallCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What you unlock")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "1A1D2B"))

            VStack(spacing: 9) {
                ForEach(premiumFeatures.prefix(4)) { feature in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Color(hex: "FF5C95"))
                            .clipShape(Circle())

                        Text(feature.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "2C3044"))

                        Spacer(minLength: 0)
                    }
                }
            }
            
            // Re-using CompactPlanCard logic but strictly for the Mini view if needed, 
            // or just keeping the existing OnboardingPlanRow for minimizing change risk
             VStack(spacing: 8) {
                ForEach(SubscriptionManager.Plan.allCases) { plan in
                    let isSelected = selectedPlan == plan
                    OnboardingPlanRow(
                        title: plan == .weekly ? "Weekly" : "Monthly",
                        subtitle: plan == .monthly ? "Best value" : "Fast start",
                        price: "\(subscriptionManager.displayPrice(for: plan))/\(plan.periodLabel)",
                        isSelected: isSelected
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedPlan = plan
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
}

private struct OnboardingPlanRow: View {
    let title: String
    let subtitle: String
    let price: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "1A1D2B"))
                        if subtitle == "Best value" {
                            Text("POPULAR")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(Color(hex: "FF5C95"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: "FFF0F5"))
                                .cornerRadius(8)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "8A92A6"))
                }

                Spacer()

                Text(price)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "1A1D2B"))

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? Color(hex: "FF5C95") : Color(hex: "D1D5DB"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color(hex: "FFF0F5") : Color(hex: "FAFAFA"))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: "FF5C95") : Color(hex: "E5E7EB"), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
