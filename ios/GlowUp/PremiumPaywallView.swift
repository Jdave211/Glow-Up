import SwiftUI

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    private var monthlyPrice: String {
        subscriptionManager.monthlyProduct?.displayPrice ?? "$1.99"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FFF0F5"), Color(hex: "FFE4E1")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "FF6B9D").opacity(0.1))
                        .frame(width: 200, height: 200)
                        .blur(radius: 40)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 80))
                        .foregroundColor(Color(hex: "FF6B9D"))
                        .symbolEffect(.bounce, value: subscriptionManager.purchaseInProgress)
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
                
                Text("Upgrade to GlowUp+")
                    .font(.custom("Didot", size: 32))
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Text("Unlock your best self with advanced AI.")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "888888"))
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                
                VStack(spacing: 24) {
                    BenefitRow(icon: "chart.xyaxis.line", color: "9B6BFF", title: "Agentic Progress Tracking", subtitle: "Visualize skin improvement over time.")
                    BenefitRow(icon: "message.fill", color: "FF6B9D", title: "Smart Chat", subtitle: "Premium dermatologist in your pocket.")
                    BenefitRow(icon: "magnifyingglass", color: "FFB800", title: "Smart Price Scouring", subtitle: "Our agents find the lowest prices for you.")
                    BenefitRow(icon: "shippingbox.fill", color: "4ECDC4", title: "Free Shipping", subtitle: "Free shipping to North American customers.")
                    BenefitRow(icon: "bag.fill", color: "FF6B9D", title: "Expanded Catalogue", subtitle: "Access to 500+ premium brands.")
                }
                .padding(.horizontal, 30)
                
                Spacer()

                if let error = subscriptionManager.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "C1466F"))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                        .multilineTextAlignment(.center)
                }
                
                if subscriptionManager.isPremium {
                    VStack(spacing: 12) {
                        Text("You are a GlowUp+ member ✨")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                        
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                openURL(url)
                            }
                        }) {
                            Text("Manage Subscription")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color(hex: "888888"))
                        }
                    }
                    .padding(.bottom, 40)
                } else {
                    Button(action: {
                        Task {
                            _ = await subscriptionManager.purchaseMonthly()
                        }
                    }) {
                        ZStack {
                            Text("Upgrade for \(monthlyPrice)/mo")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .opacity(subscriptionManager.purchaseInProgress ? 0 : 1)

                            if subscriptionManager.purchaseInProgress {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "FF6B9D"), Color(hex: "FF8AAF")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color(hex: "FF6B9D").opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .disabled(subscriptionManager.purchaseInProgress)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 10)

                    Button(action: {
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    }) {
                        Text("Restore Purchases")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "888888"))
                    }
                    .padding(.bottom, 8)
                    
                    Text("Cancel anytime. Terms apply.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "AAAAAA"))
                        .padding(.bottom, 20)
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(Color(hex: "D1C4C9"))
                            .padding(20)
                    }
                }
                Spacer()
            }
        }
        .task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.refreshEntitlements()
        }
    }
}

struct MiniPostOnboardingPaywallView: View {
    let onUpgradeSuccess: () -> Void
    let onContinueFree: () -> Void

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showFullBenefits = false

    private var monthlyPrice: String {
        subscriptionManager.monthlyProduct?.displayPrice ?? "$1.99"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FFF6FA"), Color(hex: "FFE8F1")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Text("One Last Step")
                    .font(.custom("Didot", size: 34))
                    .foregroundColor(Color(hex: "2D2D2D"))

                Text("Start GlowUp+ right after onboarding for faster results and smarter support.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "666666"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                VStack(spacing: 12) {
                    if showFullBenefits {
                        BenefitRow(icon: "chart.xyaxis.line", color: "9B6BFF", title: "Agentic Progress Tracking", subtitle: "See measurable changes over time.")
                        BenefitRow(icon: "message.fill", color: "FF6B9D", title: "Smart Chat", subtitle: "Premium dermatologist in your pocket.")
                        BenefitRow(icon: "shippingbox.fill", color: "4ECDC4", title: "Free Shipping", subtitle: "Free shipping to North American customers.")
                        BenefitRow(icon: "magnifyingglass", color: "FFB800", title: "Smart Price Scouring", subtitle: "Agents find better prices for your routine.")
                    } else {
                        Text("Includes smart chat, premium dermatologist support in your pocket, and free shipping to North American customers.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "555555"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        Button("See all benefits") {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showFullBenefits = true
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.82))
                .cornerRadius(18)
                .padding(.horizontal, 20)

                if let error = subscriptionManager.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "C1466F"))
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button(action: {
                    Task {
                        let success = await subscriptionManager.purchaseMonthly()
                        if success {
                            onUpgradeSuccess()
                        }
                    }
                }) {
                    ZStack {
                        Text("Start GlowUp+ for \(monthlyPrice)/mo")
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
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "FF6B9D"), Color(hex: "FF8AAF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }
                .disabled(subscriptionManager.purchaseInProgress)
                .padding(.horizontal, 24)

                Button(action: {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.isPremium {
                            onUpgradeSuccess()
                        }
                    }
                }) {
                    Text("Restore Purchases")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "888888"))
                }
                .padding(.top, 6)

                Button(action: onContinueFree) {
                    Text("Continue with Free Plan")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "777777"))
                }
                .padding(.bottom, 8)

                Text("Cancel anytime. Terms apply.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "AAAAAA"))
                    .padding(.bottom, 26)
            }
        }
        .task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.refreshEntitlements()
            if subscriptionManager.isPremium {
                onUpgradeSuccess()
            }
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let color: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: color).opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: color))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "888888"))
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
