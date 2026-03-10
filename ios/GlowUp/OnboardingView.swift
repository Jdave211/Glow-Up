import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    private struct WelcomeFeature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
    }

    let onComplete: (_ userId: String) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentImageIndex = 0
    @State private var signInErrorMessage: String?
    @State private var showSignInError = false
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private let backgroundImages = ["welcomebg1", "welcomebg2", "welcomebg3"]
    private let subtitles = [
        "A few photos in. A sharper routine, product plan, and progress dashboard out.",
        "GlowUp turns selfies into technique guidance, skincare picks, and measurable check-ins.",
        "Built for people who want structure, not vague beauty advice."
    ]
    private let featurePills = ["Photo-led analysis", "Routine roadmap", "Progress tracking"]
    private let welcomeFeatures = [
        WelcomeFeature(icon: "camera.macro", title: "Analyze photos", subtitle: "Find what to improve first."),
        WelcomeFeature(icon: "list.bullet.clipboard", title: "Build a routine", subtitle: "Get steps that fit your skin."),
        WelcomeFeature(icon: "chart.line.uptrend.xyaxis", title: "Track change", subtitle: "See your check-ins stack up."),
        WelcomeFeature(icon: "lock.shield", title: "Stay synced", subtitle: "Keep everything tied to one account.")
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                rotatingBackground(in: proxy)

                VStack(alignment: .leading, spacing: 0) {
                    topBrandRow(safeTop: proxy.safeAreaInsets.top)
                    Spacer(minLength: 24)

                    VStack(alignment: .leading, spacing: 20) {
                        pageDots

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Photo-led beauty,\nbut structured.")
                                .font(.custom("Didot", size: headlineSize(for: proxy)))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineSpacing(4)

                            Text(subtitles[currentImageIndex])
                                .font(.system(size: horizontalSizeClass == .regular ? 19 : 17, weight: .medium))
                                .foregroundColor(Color(hex: "FFD9E8"))
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .id("subtitle-\(currentImageIndex)")
                        }

                        featurePillRow

                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(welcomeFeatures) { feature in
                                welcomeFeatureCard(feature)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SignInWithAppleButton(
                                .signIn,
                                onRequest: { request in
                                    request.requestedScopes = [.fullName, .email]
                                },
                                onCompletion: { result in
                                    switch result {
                                    case .success(let authResults):
                                        handleAuthorization(authResults)
                                    case .failure(let error):
                                        showAuthError(error.localizedDescription)
                                    }
                                }
                            )
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            Text("Sign in to keep your photos, routines, chat, and progress synced across sessions.")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.74))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 10))
                    .background(
                        LinearGradient(
                            colors: [
                                Color(hex: "241728").opacity(0.94),
                                Color(hex: "150E1D").opacity(0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: Color.black.opacity(0.22), radius: 28, x: 0, y: 18)
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 1.2)) {
                    currentImageIndex = (currentImageIndex + 1) % backgroundImages.count
                }
            }
        }
        .alert("Sign In Failed", isPresented: $showSignInError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInErrorMessage ?? "We couldn't sign you in right now. Please try again.")
        }
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 640 : .infinity
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private func headlineSize(for proxy: GeometryProxy) -> CGFloat {
        if horizontalSizeClass == .regular { return 52 }
        return min(48, max(38, proxy.size.width * 0.115))
    }

    private func rotatingBackground(in proxy: GeometryProxy) -> some View {
        TabView(selection: $currentImageIndex) {
            ForEach(0..<backgroundImages.count, id: \.self) { index in
                Image(backgroundImages[index])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay(
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.12),
                        Color.black.opacity(0.28),
                        Color(hex: "2B1834").opacity(0.86),
                        Color(hex: "120B19")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [Color(hex: "FF8FB7").opacity(0.28), .clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 460
                )
            }
        )
    }

    private func topBrandRow(safeTop: CGFloat) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Text("GlowUp")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.22))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(Capsule())

            Spacer()

            Text("Private account experience")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.88))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.top, safeTop + 12)
        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(backgroundImages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentImageIndex ? Color(hex: "FF8FB7") : Color.white.opacity(0.18))
                    .frame(width: index == currentImageIndex ? 28 : 8, height: 8)
            }
        }
    }

    private var featurePillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(featurePills, id: \.self) { pill in
                    Text(pill)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
        }
        .scrollClipDisabled()
    }

    private func welcomeFeatureCard(_ feature: WelcomeFeature) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: feature.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "FFB1CA"))
            }

            Text(feature.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            Text(feature.subtitle)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(14)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    func handleAuthorization(_ result: ASAuthorization) {
        if let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential {
            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                showAuthError("Missing Apple identity token. Please try again.")
                return
            }
            
            let fullName = appleIDCredential.fullName
            
            Task {
                do {
                    let user = try await SupabaseService.shared.signInWithApple(identityToken: identityToken, fullName: fullName)
                    
                    if let user = user {
                        SessionManager.shared.saveUser(user)
                        if user.onboarded == true {
                            SessionManager.shared.markOnboarded()
                        }
                        await MainActor.run { onComplete(user.id) }
                    } else {
                        await MainActor.run {
                            showAuthError("Sign in succeeded but no user profile was returned.")
                        }
                    }
                } catch {
                    await MainActor.run {
                        showAuthError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func showAuthError(_ message: String) {
        signInErrorMessage = message
        showSignInError = true
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(onComplete: { _ in })
    }
}
