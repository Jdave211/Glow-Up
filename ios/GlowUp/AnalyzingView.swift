import SwiftUI

struct AnalyzingView: View {
    @Binding var result: AnalysisResult?
    let onComplete: () -> Void
    
    @State private var iconPulse: CGFloat = 1.0
    @State private var haloRotation: Double = 0
    @State private var glassDrift: CGFloat = -22
    @State private var elapsedTicks: Int = 0

    private let loadingStages = [
        "Analyzing your photos + profile",
        "Scoring where you can improve first",
        "Building technique and product recommendations"
    ]

    private var currentStage: String {
        let idx = min(elapsedTicks / 8, loadingStages.count - 1)
        return loadingStages[idx]
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "F8DCEC"),
                    Color(hex: "FDEAF4"),
                    Color(hex: "FFF8FB")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 240, height: 240)
                .blur(radius: 24)
                .offset(x: -125, y: -250)

            Circle()
                .fill(Color(hex: "FFC8DE").opacity(0.42))
                .frame(width: 280, height: 280)
                .blur(radius: 26)
                .offset(x: 130, y: 260)

            RoundedRectangle(cornerRadius: 50, style: .continuous)
                .fill(Color.white.opacity(0.2))
                .frame(width: 320, height: 320)
                .blur(radius: 2)
                .offset(y: glassDrift)
            
            VStack(spacing: 18) {
                Spacer()

                ZStack {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 102, height: 102)
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1.2)
                                .frame(width: 118, height: 118)
                                .rotationEffect(.degrees(haloRotation))
                            Text("✨")
                                .font(.system(size: 38))
                        }
                        .scaleEffect(iconPulse)

                        Text("Building your glow-up plan")
                            .font(.custom("Didot", size: 34))
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "252638"))
                            .multilineTextAlignment(.center)

                        Text(currentStage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "5A5E72"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        ProgressView()
                            .tint(Color(hex: "FF6B9D"))
                            .scaleEffect(1.1)

                        Text("Usually completes in under 20 seconds.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "8387A0"))
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 30)
                }
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.white.opacity(0.74), lineWidth: 1)
                        )
                )
                .shadow(color: Color(hex: "8D5878").opacity(0.22), radius: 24, x: 0, y: 12)
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
        .onAppear {
            startAnimations()
            checkForCompletion()
        }
    }
    
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
            iconPulse = 1.07
        }

        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            haloRotation = 360
        }

        withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
            glassDrift = 20
        }
    }
    
    private func checkForCompletion() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            elapsedTicks += 1
            
            if result != nil {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onComplete()
                }
            }
        }
    }
}

struct AnalyzingView_Previews: PreviewProvider {
    static var previews: some View {
        AnalyzingView(result: .constant(nil), onComplete: {})
    }
}
