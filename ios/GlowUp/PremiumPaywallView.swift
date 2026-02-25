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

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @State private var selectedPlan: SubscriptionManager.Plan = .monthly
    @State private var skinTone: Double?
    
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
            ZStack(alignment: .bottom) {
                // 1. Background Image (Top Half)
                // We let it take up more space, but cover the top
                VStack(spacing: 0) {
                    Image(backgroundImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.55)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Spacer()
                }
                .ignoresSafeArea()
                
                // 2. Main Content (Bottom Sheet style, but fixed)
                VStack(spacing: 0) {
                    // Header Text (Overlapping the image slightly or just inside the sheet?)
                    // Let's put the header TEXT inside the ZStack over the image, 
                    // and the rest in the white sheet.
                }
                
                // Header Text Overlay
                VStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Unlock Your\nBest Skin")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        Text("Join thousands transforming their skin.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .padding(.bottom, proxy.size.height * 0.48) // Push up above the sheet
                }
                .ignoresSafeArea()
                .frame(width: proxy.size.width)
                
                // Bottom Sheet (White Background)
                ZStack {
                    Color.white
                        .clipShape(RoundedCorner(radius: 32, corners: [.topLeft, .topRight]))
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -5)
                    
                    VStack(spacing: 16) {
                        // Features Grid (Compact)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(premiumFeatures) { feature in
                                HStack(spacing: 8) {
                                    Image(systemName: feature.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color(hex: "FF5C95"))
                                        .frame(width: 24, height: 24)
                                        .background(Color(hex: "FFF0F5"))
                                        .clipShape(Circle())
                                    
                                    Text(feature.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(Color(hex: "1A1D2B"))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .background(Color(hex: "F9FAFB"))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.top, 24)
                        
                        // Plan Selection (Horizontal)
                        HStack(spacing: 12) {
                            ForEach(SubscriptionManager.Plan.allCases) { plan in
                                CompactPlanCard(
                                    plan: plan,
                                    price: subscriptionManager.displayPrice(for: plan),
                                    isSelected: selectedPlan == plan
                                ) {
                                    withAnimation(.spring()) {
                                        selectedPlan = plan
                                    }
                                }
                            }
                        }
                        
                        // CTA
                        Button(action: {
                            Task {
                                _ = await subscriptionManager.purchase(plan: selectedPlan)
                            }
                        }) {
                            ZStack {
                                Text(ctaTitle)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .opacity(subscriptionManager.purchaseInProgress ? 0 : 1)
                                
                                if subscriptionManager.purchaseInProgress {
                                    ProgressView().tint(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "FF5C95"))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(hex: "FF5C95").opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .disabled(subscriptionManager.purchaseInProgress || subscriptionManager.isLoadingProducts)
                        
                        // Footer
                        HStack(spacing: 16) {
                            Button("Restore") { Task { await subscriptionManager.restorePurchases() } }
                            Button("Terms") { openURL(termsOfServiceURL) }
                            Button("Privacy") { openURL(privacyPolicyURL) }
                            Button("Support") { openURL(supportURL) }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "8A92A6"))
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 20)
                    // Ensure it fits within the bottom area
                }
                .frame(height: proxy.size.height * 0.45) // Takes bottom 45%
            }
            
            // Close Button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 50)
                .padding(.trailing, 20)
                Spacer()
            }
        }
        .task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.refreshEntitlements()
            if let userId = SessionManager.shared.userId {
                if let profile = try? await SupabaseService.shared.getSkinProfile(userId: userId) {
                    self.skinTone = profile.skinTone
                }
            }
        }
    }
}

// MARK: - Components

struct CompactPlanCard: View {
    let plan: SubscriptionManager.Plan
    let price: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if plan == .monthly {
                    Text("BEST VALUE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "FF5C95"))
                        .cornerRadius(4)
                } else {
                    Text("FLEXIBLE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(Color(hex: "8A92A6"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "F3F4F6"))
                        .cornerRadius(4)
                }
                
                Text(plan == .weekly ? "Weekly" : "Monthly")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "1A1D2B"))
                
                Text(price)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "57607A"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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

// Helper for rounded corners on specific sides
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// Keep MiniPostOnboardingPaywallView mostly as is, just ensuring it compiles
struct MiniPostOnboardingPaywallView: View {
    let onUpgradeSuccess: () -> Void
    let onContinueFree: () -> Void

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

                Text("Start with photo-led recommendations right after onboarding.")
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

                HStack(spacing: 20) {
                    Button("Restore") {
                        Task {
                            await subscriptionManager.restorePurchases()
                            if subscriptionManager.isPremium {
                                onUpgradeSuccess()
                            }
                        }
                    }

                    Button("Continue Free") {
                        onContinueFree()
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
