import SwiftUI

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPremium = SessionManager.shared.isPremium
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: [Color(hex: "FFF0F5"), Color(hex: "FFE4E1")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Image / Illustration
                ZStack {
                    Circle()
                        .fill(Color(hex: "FF6B9D").opacity(0.1))
                        .frame(width: 200, height: 200)
                        .blur(radius: 40)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 80))
                        .foregroundColor(Color(hex: "FF6B9D"))
                        .symbolEffect(.bounce, options: .repeating)
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
                
                // Title
                Text("Upgrade to GlowUp+")
                    .font(.custom("Didot", size: 32))
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Text("Unlock your best self with advanced AI.")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "888888"))
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                
                // Benefits List
                VStack(spacing: 24) {
                    BenefitRow(icon: "chart.xyaxis.line", color: "9B6BFF", title: "Agentic Progress Tracking", subtitle: "Visualize skin improvement over time.")
                    BenefitRow(icon: "magnifyingglass", color: "FFB800", title: "Smart Price Scouring", subtitle: "Our agents find the lowest prices for you.")
                    BenefitRow(icon: "shippingbox.fill", color: "4ECDC4", title: "Free Shipping", subtitle: "Unlimited free delivery across North America.")
                    BenefitRow(icon: "bag.fill", color: "FF6B9D", title: "Expanded Catalogue", subtitle: "Access to 500+ premium brands.")
                }
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Action Button
                if isPremium {
                    VStack(spacing: 12) {
                        Text("You are a GlowUp+ member ✨")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                        
                        Button(action: {
                            // Cancel Logic (Simulated)
                            SessionManager.shared.isPremium = false
                            isPremium = false
                        }) {
                            Text("Manage Subscription")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color(hex: "888888"))
                        }
                    }
                    .padding(.bottom, 40)
                } else {
                    Button(action: {
                        // Upgrade Logic (Simulated)
                        SessionManager.shared.isPremium = true
                        isPremium = true
                        // Confetti or success state?
                    }) {
                        Text("Upgrade for $1.99/mo")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
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
                    .padding(.horizontal, 30)
                    .padding(.bottom, 16)
                    
                    Text("Cancel anytime. Terms apply.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "AAAAAA"))
                        .padding(.bottom, 30)
                }
            }
            
            // Close Button
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
    }
}

struct MiniPostOnboardingPaywallView: View {
    let onUpgrade: () -> Void
    let onContinueFree: () -> Void
    @State private var showFullBenefits = false

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

                Text("Start GlowUp+ right after onboarding for faster results.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "666666"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                VStack(spacing: 12) {
                    if showFullBenefits {
                        BenefitRow(icon: "chart.xyaxis.line", color: "9B6BFF", title: "Agentic Progress Tracking", subtitle: "See measurable changes over time.")
                        BenefitRow(icon: "shippingbox.fill", color: "4ECDC4", title: "Free Shipping", subtitle: "Save on every order, automatically.")
                        BenefitRow(icon: "magnifyingglass", color: "FFB800", title: "Smart Price Scouring", subtitle: "Agents find better prices for your routine.")
                    } else {
                        Text("Includes free shipping, smarter product matching, and progress tracking.")
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

                Spacer()

                Button(action: onUpgrade) {
                    Text("Start GlowUp+ for $1.99/mo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
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
                .padding(.horizontal, 24)

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

