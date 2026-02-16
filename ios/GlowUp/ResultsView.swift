import SwiftUI

struct ResultsView: View {
    let result: AnalysisResult
    let onRestart: () -> Void
    @State private var selectedTab: RoutineTab = .morning
    
    enum RoutineTab: String, CaseIterable {
        case morning = "AM ☀️"
        case evening = "PM 🌙"
    }
    
    var products: [InferenceProduct] {
        // Prefer inference products if available
        if let inferenceProducts = result.inference?.products {
            return inferenceProducts
        }
        // Fallback to legacy agent recommendations
        if let recommendations = result.agents[safe: 2]?.recommendations.value as? [[String: Any]] {
            return recommendations.compactMap { dict -> InferenceProduct? in
                guard let id = dict["id"] as? String,
                      let name = dict["name"] as? String,
                      let brand = dict["brand"] as? String,
                      let price = dict["price"] as? Double,
                      let category = dict["category"] as? String else { return nil }
                return InferenceProduct(
                    id: id,
                    name: name,
                    brand: brand,
                    price: price,
                    category: category,
                    description: dict["description"] as? String,
                    image_url: dict["image_url"] as? String,
                    rating: dict["rating"] as? Double,
                    similarity: dict["similarity"] as? Double,
                    buy_link: dict["buy_link"] as? String
                )
            }
        }
        return []
    }
    
    var morningSteps: [RoutineStep] {
        result.inference?.routine?.morning ?? result.summary.routine?.morning ?? []
    }
    
    var eveningSteps: [RoutineStep] {
        result.inference?.routine?.evening ?? result.summary.routine?.evening ?? []
    }
    
    var personalizedTips: [String] {
        result.inference?.personalized_tips ?? result.summary.personalized_tips ?? []
    }
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "FFF0F5"), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("your glow up ✨")
                                .font(.system(size: 28, weight: .heavy))
                                .foregroundColor(Color(hex: "2D2D2D"))
                        }
                        
                        Spacer()
                        
                        // Confidence circle
                        ZStack {
                            Circle()
                                .fill(Color(hex: "FFE4EC"))
                                .frame(width: 70, height: 70)
                            VStack(spacing: 2) {
                                Text("\(Int((Double(result.summary.overallConfidence) ?? 0) * 100))%")
                                    .font(.system(size: 20, weight: .heavy))
                                    .foregroundColor(Color(hex: "FF6B9D"))
                                Text("match")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(hex: "FF8FB1"))
                            }
                        }
                    }
                    .padding(.top, 20)
                    
                    // Stats row
                    HStack(spacing: 12) {
                        ResultsStatCard(value: "\(result.summary.totalProducts)", label: "products")
                        ResultsStatCard(value: "$\(Int(result.summary.totalCost))", label: "total")
                        ResultsStatCard(value: "$\(Int(result.summary.totalCost * 0.3))", label: "/month")
                    }
                    
                    // Personalized Routine Section (NEW!)
                    if !morningSteps.isEmpty || !eveningSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("your routine 🌸")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(hex: "2D2D2D"))
                            
                            // Tab selector
                            HStack(spacing: 0) {
                                ForEach(RoutineTab.allCases, id: \.self) { tab in
                                    Button(action: { selectedTab = tab }) {
                                        Text(tab.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(selectedTab == tab ? .white : Color(hex: "FF6B9D"))
                                            .padding(.vertical, 10)
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                selectedTab == tab ?
                                                Color(hex: "FF6B9D") : Color.clear
                                            )
                                    }
                                }
                            }
                            .background(Color(hex: "FFE4EC"))
                            .cornerRadius(12)
                            
                            // Routine steps
                            let steps = selectedTab == .morning ? morningSteps : eveningSteps
                            ForEach(steps) { step in
                                ResultsRoutineStepCard(step: step)
                            }
                        }
                    }
                    
                    // Personalized Tips (NEW!)
                    if !personalizedTips.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("personalized tips 💡")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(hex: "2D2D2D"))
                            
                            ForEach(personalizedTips, id: \.self) { tip in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("✦")
                                        .foregroundColor(Color(hex: "FF6B9D"))
                                    Text(tip)
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "555555"))
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                            }
                        }
                    }
                    
                    // Products section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("recommended for you 💕")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        
                        ForEach(products) { product in
                            ResultsProductCard(product: product)
                        }
                    }
                    
                    // Agent insights
                    if !result.agents.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("AI analysis 🔮")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(hex: "2D2D2D"))
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(result.agents.enumerated()), id: \.offset) { index, agent in
                                        InsightCard(agent: agent, agentInfo: AgentInfo.agents[safe: index] ?? AgentInfo.agents[0])
                                    }
                                }
                            }
                            .padding(.horizontal, -20)
                            .padding(.leading, 20)
                        }
                    }
                    
                    // Checkout button
                    Button(action: {}) {
                        Text("shop all • $\(String(format: "%.2f", result.summary.totalCost))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "FF6B9D"), Color(hex: "FF8FB1")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                            .shadow(color: Color(hex: "FF6B9D").opacity(0.35), radius: 16, x: 0, y: 8)
                    }
                    
                    // Restart button
                    Button(action: onRestart) {
                        Text("start over 💫")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// Safe array indexing
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Results-specific views
struct ResultsStatCard: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(Color(hex: "FF6B9D"))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "888888"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color(hex: "FF6B9D").opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

struct ResultsRoutineStepCard: View {
    let step: RoutineStep
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FF6B9D"))
                    .frame(width: 32, height: 32)
                Text("\(step.step)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(step.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                if let product = step.product {
                    Text(product.name)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
                
                Text(step.instructions)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "888888"))
                    .lineLimit(2)
            }
            
            Spacer()
            
            Text(step.frequency)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "FF8FB1"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "FFE4EC"))
                .cornerRadius(8)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

struct ResultsProductCard: View {
    let product: InferenceProduct
    
    var matchPercentage: Int {
        Int((product.similarity ?? 0.5) * 100)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FFE4EC"))
                    .frame(width: 44, height: 44)
                Text("\(matchPercentage)%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "FF6B9D"))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let rating = product.rating {
                        Text("⭐ \(String(format: "%.1f", rating))")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "888888"))
                    }
                    Text(product.category)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "FFB4C8"))
                }
            }
            
            Spacer()
            
            Text("$\(product.price.roundedUpPrice)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "FF6B9D"))
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

struct InsightCard: View {
    let agent: AgentResult
    let agentInfo: AgentInfo
    
    var conclusionText: String {
        agent.thinking.first(where: { $0.conclusion != nil })?.conclusion ?? "Analysis complete"
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(agent.emoji)
                .font(.system(size: 32))
            Text(agent.agentName.components(separatedBy: " ").first ?? "")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            Text(conclusionText)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(width: 140)
        .padding(16)
        .background(Color(hex: agentInfo.color))
        .cornerRadius(20)
    }
}

#Preview {
    ResultsView(
        result: AnalysisResult(
            agents: [],
            summary: Summary(
                totalProducts: 6, 
                totalCost: 125.99, 
                overallConfidence: "0.89",
                routine: nil,
                personalized_tips: ["Test your products before full use", "Stay consistent"]
            ),
            inference: nil
        ),
        onRestart: {}
    )
}








