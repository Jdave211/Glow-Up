import SwiftUI
import MapKit
import UserNotifications

struct MainTabView: View {
    let analysisResult: AnalysisResult
    var onSignOut: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .home
    @StateObject private var cartManager = CartManager()
    @StateObject private var chatSession = ChatSession()
    
    enum Tab: String, CaseIterable {
        case home     = "Home"
        case skin     = "Skin"
        case chat     = "Chat"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .home:     return "house.fill"
            case .skin:     return "sparkles"
            case .chat:     return "bubble.left.and.text.bubble.right.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    var body: some View {
        Group {
            // Page content - conditional views instead of TabView
            switch selectedTab {
            case .home:
                HomeView(cartManager: cartManager, fallbackAnalysisResult: analysisResult)
            case .chat:
                ChatView(analysisResult: analysisResult, cartManager: cartManager, chatSession: chatSession)
            case .skin:
                SkinView()
            case .settings:
                SettingsView(onSignOut: onSignOut)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(chatTabSwipeGesture)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .onAppear {
            cartManager.loadCart(userId: SessionManager.shared.userId)
            Task {
                _ = await NotificationManager.shared.syncScheduledNotifications(userId: SessionManager.shared.userId)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                _ = await NotificationManager.shared.syncScheduledNotifications(userId: SessionManager.shared.userId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .glowUpOpenRoutineImport)) { _ in
            guard SessionManager.isRoutineSharingEnabled else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = .skin
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .glowUpNotificationDestination)) { note in
            guard let destination = note.userInfo?["destination"] as? String else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                switch destination {
                case "routine", "progress":
                    selectedTab = .skin
                case "delivery_tracking":
                    selectedTab = .home
                default:
                    break
                }
            }
        }
    }

    private var chatTabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 22, coordinateSpace: .local)
            .onEnded { value in
                guard selectedTab == .chat else { return }

                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 45 else { return }

                if horizontal < 0 {
                    selectAdjacentTab(offset: 1)
                } else {
                    selectAdjacentTab(offset: -1)
                }
            }
    }

    private func selectAdjacentTab(offset: Int) {
        guard let currentIndex = Tab.allCases.firstIndex(of: selectedTab) else { return }
        let newIndex = currentIndex + offset
        guard Tab.allCases.indices.contains(newIndex) else { return }

        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedTab = Tab.allCases[newIndex]
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.1)

            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button(action: {
                        let gen = UISelectionFeedbackGenerator()
                        gen.selectionChanged()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(selectedTab == tab ? Color(hex: "FF6B9D") : Color(hex: "B6B6BC"))
                                .overlay(alignment: .topTrailing) {
                                    if tab == .home && cartManager.itemCount > 0 {
                                        Text("\(cartManager.itemCount)")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 14, height: 14)
                                            .background(Color(hex: "FF6B9D"))
                                            .clipShape(Circle())
                                            .offset(x: 8, y: -6)
                                    }
                                }

                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedTab == tab ? Color(hex: "FF6B9D") : Color(hex: "AFAFB5"))
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(Color(hex: "F8F2F5"))
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Chat View (Looksmax AI — skin-first)
// ═══════════════════════════════════════════════════

final class ChatSession: ObservableObject {
    @Published var currentChat: [ChatMessage] = []
    @Published var currentConversationId: String?
    @Published var conversations: [SupabaseService.ChatConversation] = []
    @Published var isTyping = false
    @Published var hasLoadedHistory = false
}

struct ChatView: View {
    let analysisResult: AnalysisResult
    @ObservedObject var cartManager: CartManager
    @ObservedObject var chatSession: ChatSession
    
    @State private var messageText = ""
    @State private var showHistory = false
    @State private var showDeleteConfirm = false
    @State private var showingProductDetail: InferenceProduct?
    @State private var forceScrollToBottomTick = 0
    @State private var pendingMessageAfterConsent: String?
    @State private var showAIConsentSheet = false
    @FocusState private var isInputFocused: Bool
    
    private var userId: String? { SessionManager.shared.userId }
    var isEmpty: Bool { chatSession.currentChat.isEmpty }
    
    var body: some View {
        ZStack {
            Color(hex: "FDF6F8").ignoresSafeArea()
            
            VStack(spacing: 0) {
                topBar
                
                if isEmpty {
                    emptyState
                        .contentShape(Rectangle())
                        .onTapGesture { isInputFocused = false }
                } else {
                    conversationView
                        .contentShape(Rectangle())
                        .onTapGesture { isInputFocused = false }
                }
                
                inputBar
            }
        }
        .onAppear { loadConversations() }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(
                conversations: chatSession.conversations,
                onSelect: { conv in
                    showHistory = false
                    loadConversation(conv)
                },
                onDelete: { conv in
                    deleteConversation(conv)
                }
            )
        }
        .sheet(item: $showingProductDetail) { product in
            ProductDetailSheet(product: product, cartManager: cartManager, fit: nil, showFullFit: false)
        }
        .sheet(isPresented: $showAIConsentSheet) {
            AIDataConsentScreen(
                kind: .chat,
                onAccept: {
                    SessionManager.shared.hasAIDataConsent = true
                    showAIConsentSheet = false
                    if let pendingMessageAfterConsent {
                        send(messageOverride: pendingMessageAfterConsent)
                    }
                },
                onCancel: {
                    pendingMessageAfterConsent = nil
                    showAIConsentSheet = false
                }
            )
        }
        .alert("Delete this chat?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let convId = chatSession.currentConversationId,
                   let conv = chatSession.conversations.first(where: { $0.id == convId }) {
                    deleteConversation(conv)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove the conversation and its messages.")
        }
    }
    
    // ────────────────────────────────────────
    // MARK: Top Bar
    // ────────────────────────────────────────
    private var topBar: some View {
        HStack {
            Button(action: {
                loadConversations(force: true)
                showHistory = true
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "2D2D2D"))
            }
            
            Spacer()
            
            Text("Chat")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: "2D2D2D"))
            
            Spacer()
            
            HStack(spacing: 14) {
                if chatSession.currentConversationId != nil {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                    }
                }
                Button(action: { startNewChat() }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // ────────────────────────────────────────
    // MARK: Empty State
    // ────────────────────────────────────────
    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "FFE0EC").opacity(0.6))
                        .frame(width: 64, height: 64)
                    Image(systemName: "sparkles")
                        .font(.system(size: 26))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
                Text("Start a new chat")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                Text("Ask GlowUp AI what your photos suggest to improve,\nthen get technique + product recommendations.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "999999"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    // ────────────────────────────────────────
    // MARK: Conversation View
    // ────────────────────────────────────────
    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    ForEach(chatSession.currentChat) { message in
                        ChatBubble(
                            message: message,
                            cartManager: cartManager,
                            showingProductDetail: $showingProductDetail
                        )
                        .id(message.id)
                    }
                    if chatSession.isTyping {
                        typingIndicator.id("typing")
                    }
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chatSession.currentChat.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: chatSession.isTyping) { _, _ in if chatSession.isTyping { scrollToBottom(proxy) } }
            .onChange(of: forceScrollToBottomTick) { _, _ in scrollToBottom(proxy) }
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) {
                if chatSession.isTyping {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let last = chatSession.currentChat.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
    
    // ────────────────────────────────────────
    // MARK: Typing Indicator
    // ────────────────────────────────────────
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
                        .scaleEffect(chatSession.isTyping ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.12),
                            value: chatSession.isTyping
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
    
    // ────────────────────────────────────────
    // MARK: Input Bar
    // ────────────────────────────────────────
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: 10) {
                TextField("Ask anything...", text: $messageText, axis: .vertical)
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
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color(hex: "DDDDDD") : Color(hex: "FF6B9D")
                        )
                        .clipShape(Circle())
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.trailing, 8)
            }
            .background(Color.white)
            .cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: "EEEEEE"), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(hex: "FDF6F8"))
        }
        .padding(.bottom, 2)
    }
    
    // ────────────────────────────────────────
    // MARK: Actions
    // ────────────────────────────────────────
    
    private func send(messageOverride: String? = nil) {
        let text = (messageOverride ?? messageText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard SessionManager.shared.hasAIDataConsent else {
            pendingMessageAfterConsent = text
            showAIConsentSheet = true
            return
        }

        pendingMessageAfterConsent = nil
        messageText = ""
        isInputFocused = false
        
        let userMsg = ChatMessage(role: .user, content: text)
        withAnimation(.easeOut(duration: 0.2)) { chatSession.currentChat.append(userMsg) }
        withAnimation { chatSession.isTyping = true }
        
        let apiMessages = chatSession.currentChat.map { msg -> [String: String] in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
        }
        
        Task {
            let isFirstMessage = chatSession.currentConversationId == nil
            
            // Create conversation on first message (temporary title)
            if isFirstMessage, let uid = userId {
                let tempTitle = String(text.prefix(50))
                if let conv = try? await SupabaseService.shared.createConversation(userId: uid, title: tempTitle) {
                    await MainActor.run { chatSession.currentConversationId = conv.id }
                }
            }
            
            // Save user message to DB
            if let convId = chatSession.currentConversationId {
                try? await SupabaseService.shared.saveMessage(conversationId: convId, role: "user", content: text)
            }
            
            do {
                // Send userId so the server can dynamically fetch profile/products via tool calling
                let chatResponse = try await APIService.shared.chat(
                    messages: apiMessages,
                    userId: userId,
                    conversationId: chatSession.currentConversationId
                )
                let didMutateCart = chatResponse.actions.contains {
                    ($0.tool == "add_to_cart" || $0.tool == "remove_from_cart") && $0.ok
                }
                let didMutateRoutine = chatResponse.actions.contains {
                    ($0.tool == "update_user_routine" && $0.ok) || $0.routineUpdated
                }
                
                // Save AI response to DB (with product metadata for persistence)
                if let convId = chatSession.currentConversationId {
                    var metadata: [String: Any]? = nil
                    if !chatResponse.productMap.isEmpty {
                        // Serialize product map as [[String: Any]] array
                        var productsArray: [[String: Any]] = []
                        for (_, product) in chatResponse.productMap {
                            var p: [String: Any] = [
                                "id": product.id,
                                "name": product.name,
                                "brand": product.brand,
                                "price": product.price,
                                "category": product.category
                            ]
                            if let img = product.image_url { p["image_url"] = img }
                            if let rating = product.rating { p["rating"] = rating }
                            if let reviews = product.review_count { p["review_count"] = reviews }
                            if let link = product.buy_link { p["buy_link"] = link }
                            if let desc = product.description { p["description"] = desc }
                            if let sim = product.similarity { p["similarity"] = sim }
                            productsArray.append(p)
                        }
                        metadata = ["products": productsArray]
                    }
                    try? await SupabaseService.shared.saveMessage(conversationId: convId, role: "assistant", content: chatResponse.message, metadata: metadata)
                }
                
                // Update conversation title with LLM-generated summary
                if isFirstMessage, let convId = chatSession.currentConversationId, let smartTitle = chatResponse.title {
                    try? await SupabaseService.shared.updateConversationTitle(conversationId: convId, title: smartTitle)
                }
                
                await MainActor.run {
                    withAnimation { chatSession.isTyping = false }
                    let aiMsg = ChatMessage(role: .assistant, content: chatResponse.message, products: chatResponse.products, productMap: chatResponse.productMap)
                    withAnimation(.easeOut(duration: 0.2)) { chatSession.currentChat.append(aiMsg) }
                    if didMutateCart {
                        cartManager.loadCart(userId: userId)
                    }
                    if didMutateRoutine {
                        NotificationCenter.default.post(name: .glowUpRoutineDidUpdate, object: nil)
                    }
                }
            } catch {
                #if DEBUG
                print("❌ Chat API error: \(error)")
                #endif
                let fallback = "Sorry, I'm having trouble connecting right now. Try again in a moment! 💕"
                if let convId = chatSession.currentConversationId {
                    try? await SupabaseService.shared.saveMessage(conversationId: convId, role: "assistant", content: fallback)
                }
                await MainActor.run {
                    withAnimation { chatSession.isTyping = false }
                    let aiMsg = ChatMessage(role: .assistant, content: fallback, products: [])
                    withAnimation(.easeOut(duration: 0.2)) { chatSession.currentChat.append(aiMsg) }
                }
            }
        }
    }
    
    private func startNewChat() {
        chatSession.currentConversationId = nil
        withAnimation(.easeOut(duration: 0.2)) { chatSession.currentChat = [] }
    }
    
    private func loadConversations(force: Bool = false) {
        guard let uid = userId else { return }
        if chatSession.hasLoadedHistory && !force { return }
        Task {
            let convos = try? await SupabaseService.shared.getConversations(userId: uid)
            await MainActor.run {
                chatSession.conversations = convos ?? []
                chatSession.hasLoadedHistory = true
            }
        }
    }
    
    private func loadConversation(_ conv: SupabaseService.ChatConversation) {
        chatSession.currentConversationId = conv.id
        Task {
            let msgs = try? await SupabaseService.shared.getMessages(conversationId: conv.id)
            await MainActor.run {
                chatSession.currentChat = (msgs ?? []).map { dbMsg in
                    // Restore product map from metadata if present
                    var productMap: [String: FeedProduct] = [:]
                    if let meta = dbMsg.metadata,
                       let metaData = meta.data(using: .utf8),
                       let metaJSON = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
                       let productsArray = metaJSON["products"] as? [[String: Any]] {
                        for pDict in productsArray {
                            if let pData = try? JSONSerialization.data(withJSONObject: pDict),
                               let product = try? JSONDecoder().decode(FeedProduct.self, from: pData) {
                                productMap[product.id] = product
                            }
                        }
                    }
                    return ChatMessage(
                        role: dbMsg.role == "user" ? .user : .assistant,
                        content: dbMsg.content,
                        timestamp: ISO8601DateFormatter().date(from: dbMsg.created_at) ?? Date(),
                        productMap: productMap
                    )
                }
                forceScrollToBottomTick += 1
            }
        }
    }
    
    private func deleteConversation(_ conv: SupabaseService.ChatConversation) {
        Task {
            try? await SupabaseService.shared.deleteConversation(conversationId: conv.id)
            // If we deleted the active conversation, clear it
            if chatSession.currentConversationId == conv.id {
                await MainActor.run {
                    chatSession.currentConversationId = nil
                    chatSession.currentChat = []
                }
            }
            // Refresh list
            loadConversations(force: true)
        }
    }
}

// MARK: - Chat Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let timestamp: Date
    let products: [FeedProduct]?
    let productMap: [String: FeedProduct]
    
    init(role: ChatRole, content: String, timestamp: Date = Date(), products: [FeedProduct]? = nil, productMap: [String: FeedProduct] = [:]) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.products = products
        self.productMap = productMap
    }
    
    enum ChatRole {
        case user, assistant
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == .user }
    @ObservedObject var cartManager: CartManager
    @Binding var showingProductDetail: InferenceProduct?
    
    var body: some View {
        if isUser {
            // ── User bubble ──
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
            // ── AI response — free-flowing, no bubble, inline product cards ──
            VStack(alignment: .leading, spacing: 10) {
                // Avatar row
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
                
                // Split content by [[PRODUCT:id]] markers and render inline
                let segments = splitContentWithProducts(message.content)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let mdText):
                        if !mdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            MarkdownView(text: mdText)
                                .padding(.leading, 4)
                        }
                    case .product(let productId):
                        if let product = message.productMap[productId] {
                            ChatProductCardInline(
                                product: product,
                                isInCart: cartManager.contains(productId: product.id),
                                onOpen: { showingProductDetail = product.asInferenceProduct },
                                onAddToCart: { cartManager.addToCart(product.asInferenceProduct) }
                            )
                            .padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Content Segment (text vs inline product)

enum ContentSegment {
    case text(String)
    case product(String) // product ID
}

func splitContentWithProducts(_ content: String) -> [ContentSegment] {
    var segments: [ContentSegment] = []
    let pattern = #"\[\[PRODUCT:([^\]]+)\]\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return [.text(content)]
    }
    
    let nsContent = content as NSString
    let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
    
    var lastEnd = 0
    for match in matches {
        let matchRange = match.range
        // Text before this match
        if matchRange.location > lastEnd {
            let textBefore = nsContent.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
            segments.append(.text(textBefore))
        }
        // Extract product ID
        if match.numberOfRanges > 1 {
            let idRange = match.range(at: 1)
            let productId = nsContent.substring(with: idRange)
            segments.append(.product(productId))
        }
        lastEnd = matchRange.location + matchRange.length
    }
    
    // Remaining text after last match
    if lastEnd < nsContent.length {
        let remaining = nsContent.substring(from: lastEnd)
        segments.append(.text(remaining))
    }
    
    if segments.isEmpty { segments.append(.text(content)) }
    return segments
}

// MARK: - Inline Product Card (full-width, inside message flow)

struct ChatProductCardInline: View {
    let product: FeedProduct
    let isInCart: Bool
    let onOpen: () -> Void
    let onAddToCart: () -> Void
    
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                // Product image
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                    
                    if let url = product.image_url {
                        ProductImageView(urlString: url, size: 72)
                            .frame(width: 60, height: 60)
                            .cornerRadius(10)
                    } else {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "FFB4C8"))
                    }
                }
                
                // Product info
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.brand)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                        .lineLimit(1)
                    
                    Text(product.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "2D2D2D"))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 6) {
                        Text("$\(product.price.roundedUpPrice)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        
                        if let rating = product.rating, rating > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(hex: "FFB800"))
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "999999"))
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Add to cart button
                Button(action: onAddToCart) {
                    Image(systemName: isInCart ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(isInCart ? Color(hex: "4ECDC4") : Color(hex: "FF6B9D"))
                        .clipShape(Circle())
                }
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ChatProductCard: View {
    let product: FeedProduct
    let isInCart: Bool
    let onOpen: () -> Void
    let onAddToCart: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
                    
                    if let url = product.image_url {
                        ProductImageView(urlString: url, size: 140)
                            .frame(width: 120, height: 120)
                            .cornerRadius(12)
                    } else {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 30))
                            .foregroundColor(Color(hex: "FFB4C8"))
                    }
                }
            }
            
            Text(product.brand)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "FF6B9D"))
                .lineLimit(1)
            
            Text(product.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "2D2D2D"))
                .lineLimit(2)
            
            HStack(spacing: 8) {
                Text("$\(product.price.roundedUpPrice)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Spacer()
                
                Button(action: onAddToCart) {
                    Image(systemName: isInCart ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(isInCart ? Color(hex: "4ECDC4") : Color(hex: "FF6B9D"))
                        .clipShape(Circle())
                }
            }
            
            if let link = product.buy_link, let url = URL(string: link) {
                Link("Buy", destination: url)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "6B5BFF"))
            }
        }
        .frame(width: 150)
        .padding(10)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Markdown Renderer
// ═══════════════════════════════════════════════════

struct MarkdownView: View {
    let text: String
    
    /// Pre-clean the text: strip markdown image syntax ![alt](url)
    private var cleanedText: String {
        // Remove ![anything](anything) — model shouldn't output these
        var result = text
        if let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^\)]+\)"#) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }
    
    // ── Block types ──
    enum MdBlock {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case bullet(text: String)
        case numberedItem(number: String, text: String)
        case divider
        case codeBlock(code: String)
    }
    
    // ── Parse raw text into blocks ──
    private func parseBlocks() -> [MdBlock] {
        var blocks: [MdBlock] = []
        let lines = cleanedText.components(separatedBy: "\n")
        var i = 0
        var paragraphBuffer = ""
        
        func flushParagraph() {
            let trimmed = paragraphBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.paragraph(text: trimmed))
            }
            paragraphBuffer = ""
        }
        
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Code block ```
            if trimmed.hasPrefix("```") {
                flushParagraph()
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }
            
            // Divider ---
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                i += 1
                continue
            }
            
            // Heading # ## ### #### etc — cap display at level 3
            if let match = trimmed.range(of: #"^(#{1,6})\s+(.+)$"#, options: .regularExpression) {
                flushParagraph()
                let full = String(trimmed[match])
                let hashes = full.prefix(while: { $0 == "#" })
                let content = full.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
                let level = min(hashes.count, 3) // Cap at 3 levels for rendering
                blocks.append(.heading(level: level, text: content))
                i += 1
                continue
            }
            
            // Bullet - or •  or *  (only if followed by space)
            if let match = trimmed.range(of: #"^[-•\*]\s+(.+)$"#, options: .regularExpression) {
                flushParagraph()
                let content = String(trimmed[match])
                    .replacingOccurrences(of: #"^[-•\*]\s+"#, with: "", options: .regularExpression)
                blocks.append(.bullet(text: content))
                i += 1
                continue
            }
            
            // Numbered list 1. 2. etc
            if let _ = trimmed.range(of: #"^\d+[\.\)]\s+(.+)$"#, options: .regularExpression) {
                flushParagraph()
                let numEnd = trimmed.firstIndex(where: { $0 == "." || $0 == ")" })!
                let num = String(trimmed[trimmed.startIndex...numEnd])
                let content = String(trimmed[trimmed.index(after: numEnd)...]).trimmingCharacters(in: .whitespaces)
                blocks.append(.numberedItem(number: num, text: content))
                i += 1
                continue
            }
            
            // Empty line = paragraph break
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }
            
            // Normal text — accumulate into paragraph
            if !paragraphBuffer.isEmpty { paragraphBuffer += " " }
            paragraphBuffer += trimmed
            i += 1
        }
        
        flushParagraph()
        return blocks
    }
    
    // ── Render a block ──
    @ViewBuilder
    private func renderBlock(_ block: MdBlock) -> some View {
        switch block {
        case .heading(let level, let txt):
            let size: CGFloat = level == 1 ? 22 : (level == 2 ? 19 : 16)
            inlineMarkdown(txt)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(Color(hex: "2D2D2D"))
                .padding(.top, 8)
                .padding(.bottom, 2)
            
        case .paragraph(let txt):
            inlineMarkdown(txt)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "2D2D2D"))
                .lineSpacing(8)
                .padding(.vertical, 4)
            
        case .bullet(let txt):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "FF6B9D"))
                inlineMarkdown(txt)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .lineSpacing(5)
            }
            .padding(.leading, 4)
            
        case .numberedItem(let num, let txt):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(num)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "FF6B9D"))
                    .frame(minWidth: 20, alignment: .trailing)
                inlineMarkdown(txt)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .lineSpacing(5)
            }
            .padding(.leading, 4)
            
        case .divider:
            Rectangle()
                .fill(Color(hex: "E8D4DB").opacity(0.5))
                .frame(height: 1)
                .padding(.vertical, 8)
            
        case .codeBlock(let code):
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(hex: "2D2D2D"))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "F5EEF1"))
                .cornerRadius(10)
        }
    }
    
    // ── Inline markdown (bold, italic, code, bold-italic) ──
    private func inlineMarkdown(_ raw: String) -> Text {
        // Parse inline spans: ***bold-italic***, **bold**, *italic*, `code`
        var result = Text("")
        var remaining = raw[raw.startIndex...]
        
        while !remaining.isEmpty {
            // Find the earliest marker
            var earliest: (range: Range<Substring.Index>, type: String)? = nil
            
            let markers: [(String, String)] = [
                ("***", "bolditalic"),
                ("**", "bold"),
                ("*", "italic"),
                ("`", "code")
            ]
            
            for (marker, type) in markers {
                if let r = remaining.range(of: marker) {
                    if earliest == nil || r.lowerBound < earliest!.range.lowerBound {
                        earliest = (r, type)
                    }
                }
            }
            
            guard let found = earliest else {
                // No more markers — append rest as plain text
                result = result + Text(String(remaining))
                break
            }
            
            // Append text before the marker
            if found.range.lowerBound > remaining.startIndex {
                result = result + Text(String(remaining[remaining.startIndex..<found.range.lowerBound]))
            }
            
            // Find matching closing marker
            let afterOpen = found.range.upperBound
            let marker: String
            switch found.type {
            case "bolditalic": marker = "***"
            case "bold": marker = "**"
            case "italic": marker = "*"
            case "code": marker = "`"
            default: marker = ""
            }
            
            if let closeRange = remaining[afterOpen...].range(of: marker) {
                let inner = String(remaining[afterOpen..<closeRange.lowerBound])
                switch found.type {
                case "bolditalic":
                    result = result + Text(inner).bold().italic()
                case "bold":
                    result = result + Text(inner).bold()
                case "italic":
                    result = result + Text(inner).italic()
                case "code":
                    result = result + Text(inner)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Color(hex: "C94080"))
                default:
                    result = result + Text(inner)
                }
                remaining = remaining[closeRange.upperBound...]
            } else {
                // No closing marker — treat as plain text
                result = result + Text(marker)
                remaining = remaining[afterOpen...]
            }
        }
        
        return result
    }
}

// MARK: - Chat History Sheet (timestamp-grouped)

struct ChatHistorySheet: View {
    let conversations: [SupabaseService.ChatConversation]
    let onSelect: (SupabaseService.ChatConversation) -> Void
    let onDelete: (SupabaseService.ChatConversation) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    private func parseDate(_ str: String) -> Date {
        Self.isoFormatter.date(from: str) ?? Self.isoFormatterNoFrac.date(from: str) ?? Date.distantPast
    }
    
    // Group conversations by time bucket
    private var grouped: [(label: String, items: [SupabaseService.ChatConversation])] {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday)!
        
        var today: [SupabaseService.ChatConversation] = []
        var yesterday: [SupabaseService.ChatConversation] = []
        var last7: [SupabaseService.ChatConversation] = []
        var last30: [SupabaseService.ChatConversation] = []
        var older: [SupabaseService.ChatConversation] = []
        
        for conv in conversations {
            let d = parseDate(conv.updated_at)
            if d >= startOfToday {
                today.append(conv)
            } else if d >= startOfYesterday {
                yesterday.append(conv)
            } else if d >= sevenDaysAgo {
                last7.append(conv)
            } else if d >= thirtyDaysAgo {
                last30.append(conv)
            } else {
                older.append(conv)
            }
        }
        
        var result: [(String, [SupabaseService.ChatConversation])] = []
        if !today.isEmpty     { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !last7.isEmpty     { result.append(("Last 7 Days", last7)) }
        if !last30.isEmpty    { result.append(("Last 30 Days", last30)) }
        if !older.isEmpty     { result.append(("Older", older)) }
        return result
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "FDF6F8").ignoresSafeArea()
                
                if conversations.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("No chat history yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "999999"))
                        Text("Start a conversation and it'll show up here.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "BBBBBB"))
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(grouped, id: \.label) { section in
                                // Section header
                                Text(section.label.uppercased())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "BBBBBB"))
                                    .tracking(0.3)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 24)
                                    .padding(.bottom, 10)
                                
                                ForEach(section.items, id: \.id) { conv in
                                    Button(action: { onSelect(conv) }) {
                                        HStack(spacing: 14) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(conv.title)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(Color(hex: "2D2D2D"))
                                                    .lineLimit(1)
                                                
                                                Text(formatTime(conv.updated_at))
                                                    .font(.system(size: 12))
                                                    .foregroundColor(Color(hex: "999999"))
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(Color(hex: "CCCCCC"))
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 2)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            onDelete(conv)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            
                            Spacer(minLength: 40)
                        }
                    }
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "666666"))
                    }
                }
            }
        }
    }
    
    private func formatTime(_ isoStr: String) -> String {
        let date = parseDate(isoStr)
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Settings View
// ═══════════════════════════════════════════════════

struct SettingsView: View {
    private let privacyPolicyURL = URL(string: "https://boiled-education-5d3.notion.site/GlowUp-Privacy-Policy-867796a49e504c3d839ce15de6ade6f3?source=copy_link")!
    private let termsOfServiceURL = URL(string: "https://boiled-education-5d3.notion.site/GlowUp-Terms-of-Service-a17b8e90751743dba5a33e2a03dd4b64?source=copy_link")!
    private let supportURL = URL(string: "https://boiled-education-5d3.notion.site/GlowUp-Support-b4226f97acba41e3bd4803fa1d0624fb?source=copy_link")!

    var onSignOut: (() -> Void)?
    @Environment(\.openURL) private var openURL
    @AppStorage("glowup.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("glowup.notifications.routine") private var routineReminders = true
    @AppStorage("glowup.notifications.photo") private var photoReminders = true
    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteAccountErrorAlert = false
    @State private var deleteAccountErrorMessage = ""
    @State private var isDeletingAccount = false
    @State private var showLooksSheet = false
    @State private var showPaywall = false
    @State private var showNotificationAlert = false
    @State private var notificationAlertMessage = ""
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.custom("Didot", size: 34))
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "1A1D2B"))
                    Text("Manage your photo-led glow-up essentials")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "8A92A6"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                // Premium Section
                settingsSection(title: "Membership", subtitle: nil) { // Removed subtitle from section header to reduce clutter
                    Button(action: { showPaywall = true }) {
                        HStack(spacing: 16) {
                            // Icon with glowing effect
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: SessionManager.shared.isPremium ? 
                                                [Color(hex: "FFD700"), Color(hex: "FFA500")] : 
                                                [Color(hex: "FF6B9D"), Color(hex: "FF8FB7")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)
                                    .shadow(color: (SessionManager.shared.isPremium ? Color.orange : Color(hex: "FF6B9D")).opacity(0.25), radius: 8, x: 0, y: 4)
                                
                                Image(systemName: SessionManager.shared.isPremium ? "crown.fill" : "sparkles")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .symbolEffect(.bounce, value: showPaywall)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(SessionManager.shared.isPremium ? "GlowUp+ Active" : "Get GlowUp+")
                                        .font(.system(size: 17, weight: .bold)) // Slightly larger
                                        .foregroundColor(Color(hex: "1A1D2B"))
                                    
                                    if SessionManager.shared.isPremium {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "FFD700"))
                                    }
                                }
                                
                                Text(SessionManager.shared.isPremium ? "Manage subscription" : "Unlock unlimited analysis & matches")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(hex: "8A92A6"))
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            if !SessionManager.shared.isPremium {
                                Text("UPGRADE")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color(hex: "FF6B9D"))
                                            .shadow(color: Color(hex: "FF6B9D").opacity(0.3), radius: 4, x: 0, y: 2)
                                    )
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "C4C4C4"))
                            }
                        }
                        .padding(.vertical, 4) // Add internal breathing room
                    }
                }

                
                // Account Section
                settingsSection(title: "Account", subtitle: "Your profile") {
                    // Profile row
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(hex: "FF6B9D"), Color(hex: "FFB4C8")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 56, height: 56) // Larger avatar
                                .shadow(color: Color(hex: "FF6B9D").opacity(0.25), radius: 6, x: 0, y: 3)
                            
                            Text(String((SessionManager.shared.userName ?? "G").prefix(1)).uppercased())
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SessionManager.shared.userName ?? "User")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Color(hex: "1A1D2B"))
                            
                            Text(SessionManager.shared.userEmail ?? "Not signed in")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "8A92A6"))
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // Notifications Section
                settingsSection(title: "Notifications", subtitle: "Stay on track without the noise") {
                    SettingsToggle(
                        icon: "bell.fill",
                        iconColor: Color(hex: "FF6B9D"),
                        title: "Push Notifications",
                        isOn: $notificationsEnabled
                    )
                    
                    if notificationsEnabled {
                        Spacer().frame(height: 16)
                        
                        SettingsToggle(
                            icon: "clock.fill",
                            iconColor: Color(hex: "9B6BFF"),
                            title: "Routine Reminders",
                            subtitle: "Daily morning & evening",
                            isOn: $routineReminders
                        )
                        
                        Spacer().frame(height: 16)
                        
                        SettingsToggle(
                            icon: "camera.fill",
                            iconColor: Color(hex: "4ECDC4"),
                            title: "Photo Check-ins",
                            subtitle: "Biweekly on Sundays",
                            isOn: $photoReminders
                        )
                    }
                }
                
                // Looks Section
                settingsSection(title: "Looks", subtitle: "Tune your photo-led plan and insights") {
                    SettingsRow(
                        icon: "sparkles",
                        iconColor: Color(hex: "FF6B9D"),
                        title: "Manage Looks Plan",
                        subtitle: "Photos, profile, routine, insights",
                        action: { showLooksSheet = true }
                    )
                }

                // About Section
                settingsSection(title: "About", subtitle: "Support and legal") {
                    SettingsRow(
                        icon: "doc.text",
                        iconColor: Color(hex: "888888"),
                        title: "Privacy Policy",
                        action: { openURL(privacyPolicyURL) }
                    )
                    Divider().padding(.leading, 44)
                    SettingsRow(
                        icon: "doc.plaintext",
                        iconColor: Color(hex: "888888"),
                        title: "Terms of Service",
                        action: { openURL(termsOfServiceURL) }
                    )
                    Divider().padding(.leading, 44)
                    SettingsRow(
                        icon: "questionmark.circle",
                        iconColor: Color(hex: "888888"),
                        title: "Help & Support",
                        action: { openURL(supportURL) }
                    )
                    Divider().padding(.leading, 44)
                    
                    HStack(spacing: 14) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(hex: "888888"))
                            .frame(width: 30)
                        
                        Text("Version")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "2D2D2D"))
                        
                        Spacer()
                        
                        Text("1.0.0")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "AAAAAA"))
                    }
                }
                
                // Sign Out
                Button(action: { showSignOutAlert = true }) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "FFF0F0"))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(hex: "FF6B6B"))
                        }
                        
                        Text("Sign Out")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B6B"))
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
                }
                .padding(.horizontal, 20)

                Button(action: { showDeleteAccountAlert = true }) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "FFE8EE"))
                                .frame(width: 36, height: 36)

                            if isDeletingAccount {
                                ProgressView()
                                    .tint(Color(hex: "D64545"))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color(hex: "D64545"))
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isDeletingAccount ? "Deleting Account..." : "Delete Account")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(hex: "D64545"))
                            Text("Permanently remove your data")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "B86A76"))
                        }

                        Spacer()
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)
                .opacity(isDeletingAccount ? 0.75 : 1.0)
                .padding(.horizontal, 20)
                
                Spacer(minLength: 120)
            }
            .padding(.top, 20)
        }
        .background(PinkDrapeBackground().ignoresSafeArea())
        .onAppear {
            configureNotificationsOnLaunch()
        }
        .onChange(of: notificationsEnabled) { _, _ in
            handleNotificationToggle()
        }
        .onChange(of: routineReminders) { _, _ in
            handleRoutineReminderToggle()
        }
        .onChange(of: photoReminders) { _, _ in
            handlePhotoReminderToggle()
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                SessionManager.shared.signOut()
                onSignOut?()
            }
        } message: {
            Text("Are you sure you want to sign out? You'll need to sign in again to access your routine.")
        }
        .alert("Notifications", isPresented: $showNotificationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notificationAlertMessage)
        }
        .alert("Delete Account Permanently?", isPresented: $showDeleteAccountAlert) {
            Button("Delete Account", role: .destructive) {
                Task { await handleDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your profile, photos, routines, chats, and progress history. This action cannot be undone.")
        }
        .alert("Couldn't Delete Account", isPresented: $showDeleteAccountErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteAccountErrorMessage)
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
        }
        .sheet(isPresented: $showLooksSheet) {
            SkincareSettingsSheet()
                .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - Section Builder
    private func settingsSection<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold)) // Slightly larger
                    .foregroundColor(Color(hex: "1A1D2B"))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "8A92A6"))
                }
            }
            .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                content()
            }
            .padding(16) // Simplified padding
            .background(Color.white)
            .cornerRadius(20) // Softer corners
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4) // Slightly deeper shadow
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Notifications
    private func configureNotificationsOnLaunch() {
        Task {
            let applied = await NotificationManager.shared.syncScheduledNotifications(userId: SessionManager.shared.userId)
            guard !applied else { return }
            await MainActor.run {
                notificationsEnabled = false
                routineReminders = false
                photoReminders = false
            }
        }
    }
    
    private func handleNotificationToggle() {
        if notificationsEnabled {
            Task {
                let applied = await NotificationManager.shared.syncScheduledNotifications(userId: SessionManager.shared.userId)
                if !applied {
                    await MainActor.run {
                        notificationsEnabled = false
                        routineReminders = false
                        photoReminders = false
                        notificationAlertMessage = "Notifications are disabled. Enable them in iOS Settings to receive reminders."
                        showNotificationAlert = true
                    }
                }
            }
        } else {
            routineReminders = false
            photoReminders = false
            NotificationManager.shared.clearAll()
        }
    }
    
    private func handleRoutineReminderToggle() {
        guard notificationsEnabled else { return }
        Task {
            let applied = await NotificationManager.shared.syncScheduledNotifications(userId: SessionManager.shared.userId)
            if !applied {
                await MainActor.run {
                    notificationsEnabled = false
                    routineReminders = false
                    photoReminders = false
                    notificationAlertMessage = "Notifications are disabled. Enable them in iOS Settings to receive reminders."
                    showNotificationAlert = true
                }
            }
        }
    }
    
    private func handlePhotoReminderToggle() {
        guard notificationsEnabled else { return }
        Task {
            let applied = await NotificationManager.shared.syncScheduledNotifications(userId: SessionManager.shared.userId)
            if !applied {
                await MainActor.run {
                    notificationsEnabled = false
                    routineReminders = false
                    photoReminders = false
                    notificationAlertMessage = "Notifications are disabled. Enable them in iOS Settings to receive reminders."
                    showNotificationAlert = true
                }
            }
        }
    }

    @MainActor
    private func handleDeleteAccount() async {
        guard !isDeletingAccount else { return }
        guard let userId = SessionManager.shared.userId else {
            SessionManager.shared.signOut()
            onSignOut?()
            return
        }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await APIService.shared.deleteAccount(userId: userId)

            let progressHistoryKey = "com.glowup.progressHistory.\(userId)"
            UserDefaults.standard.removeObject(forKey: progressHistoryKey)
            SessionManager.shared.routineLibrary = []
            NotificationManager.shared.clearAll()
            SessionManager.shared.signOut()
            onSignOut?()
        } catch {
            deleteAccountErrorMessage =
                (error as? LocalizedError)?.errorDescription ??
                error.localizedDescription
            if deleteAccountErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deleteAccountErrorMessage = "Unable to delete your account right now. Please try again."
            }
            showDeleteAccountErrorAlert = true
        }
    }
    
}

struct SettingsToggle: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "1A1D2B"))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "8A92A6"))
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .tint(Color(hex: "FF6B9D"))
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "1A1D2B"))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "8A92A6"))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "D1D1D6"))
            }
            .padding(.vertical, 4)
        }
    }
}

struct SettingsTextField: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization? = .words
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            TextField(title, text: $text)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "1A1D2B"))
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Skincare Settings Sheet
struct SkincareSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Routine Management")
                    .font(.custom("Didot", size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "1A1D2B"))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "E5E7EB"))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color(hex: "8A92A6"))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            VStack(spacing: 0) {
                SettingsRow(icon: "arrow.clockwise", iconColor: Color(hex: "FFB800"), title: "Re-run Analysis", subtitle: "Refresh your routine")
                Divider().padding(.leading, 52).opacity(0.6)
                SettingsRow(icon: "pencil", iconColor: Color(hex: "FF6B9D"), title: "Edit Skin Profile", subtitle: "Update goals and concerns")
                Divider().padding(.leading, 52).opacity(0.6)
                SettingsRow(icon: "trash", iconColor: Color(hex: "FF6B6B"), title: "Clear Saved Routine", subtitle: "Start fresh anytime")
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .background(PinkDrapeBackground().ignoresSafeArea())
    }
}

// MARK: - Shipping Settings Sheet
struct ShippingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fullName: String
    @Binding var line1: String
    @Binding var line2: String
    @Binding var city: String
    @Binding var state: String
    @Binding var zip: String
    @Binding var country: String
    let onSave: () -> Void
    @StateObject private var addressAutocomplete = AddressAutocomplete()
    @State private var showSuggestions = false
    
    private var canSave: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !zip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shipping")
                                .font(.custom("Didot", size: 32))
                                .fontWeight(.bold)
                                .foregroundColor(Color(hex: "1A1D2B"))
                            Text("Used to prefill your saved details")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "8A92A6"))
                        }
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(Color(hex: "E5E7EB"))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color(hex: "8A92A6"))
                        }
                    }
                    .padding(.top, 24)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Contact")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "8A92A6"))
                            .textCase(.uppercase)
                            .padding(.leading, 4)
                        
                        ShippingInputField(
                            label: "Full Name",
                            placeholder: "Jane Doe",
                            text: $fullName,
                            icon: "person.fill",
                            iconColor: Color(hex: "FF6B9D"),
                            contentType: .name
                        )
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Address")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "8A92A6"))
                            .textCase(.uppercase)
                            .padding(.leading, 4)
                        
                        ShippingInputField(
                            label: "Address Line 1",
                            placeholder: "123 Main Street",
                            text: $line1,
                            icon: "house.fill",
                            iconColor: Color(hex: "9B6BFF"),
                            contentType: .fullStreetAddress
                        )
                        
                        if showSuggestions && !addressAutocomplete.results.isEmpty {
                            let suggestions = Array(addressAutocomplete.results.prefix(5))
                            VStack(spacing: 0) {
                                ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, suggestion in
                                    Button(action: {
                                        addressAutocomplete.select(suggestion) { result in
                                            guard let result else { return }
                                            line1 = result.line1
                                            city = result.city
                                            state = result.state
                                            zip = result.zip
                                            country = result.country
                                            showSuggestions = false
                                        }
                                    }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(Color(hex: "1A1D2B"))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(suggestion.subtitle)
                                                .font(.system(size: 12))
                                                .foregroundColor(Color(hex: "8A92A6"))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if idx < suggestions.count - 1 {
                                        Divider().padding(.leading, 12)
                                    }
                                }
                            }
                            .background(Color(hex: "FFF8FA"))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "FFD1DC"), lineWidth: 1)
                            )
                        }
                        
                        ShippingInputField(
                            label: "Address Line 2 (Optional)",
                            placeholder: "Apt, suite, etc.",
                            text: $line2,
                            icon: "house",
                            iconColor: Color(hex: "9B6BFF"),
                            contentType: .streetAddressLine2
                        )
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Location")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "8A92A6"))
                            .textCase(.uppercase)
                            .padding(.leading, 4)
                        
                        HStack(alignment: .top, spacing: 12) {
                            ShippingInputField(
                                label: "City",
                                placeholder: "Los Angeles",
                                text: $city,
                                icon: "building.2.fill",
                                iconColor: Color(hex: "4ECDC4"),
                                contentType: .addressCity
                            )
                            ShippingInputField(
                                label: "State",
                                placeholder: "CA",
                                text: $state,
                                icon: "flag.fill",
                                iconColor: Color(hex: "FFB800"),
                                contentType: .addressState
                            )
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            ShippingInputField(
                                label: "ZIP",
                                placeholder: "90001",
                                text: $zip,
                                icon: "number",
                                iconColor: Color(hex: "FF6B9D"),
                                contentType: .postalCode,
                                keyboard: .numbersAndPunctuation,
                                autocapitalization: .never
                            )
                            ShippingInputField(
                                label: "Country",
                                placeholder: "United States",
                                text: $country,
                                icon: "globe",
                                iconColor: Color(hex: "8A92A6"),
                                contentType: .countryName
                            )
                        }
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            
            VStack(spacing: 8) {
                Button(action: {
                    onSave()
                    dismiss()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text("Save Details")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: canSave ? [Color(hex: "FF6B9D"), Color(hex: "FF8FB7")] : [Color(hex: "E5E7EB"), Color(hex: "E5E7EB")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: canSave ? Color(hex: "FF6B9D").opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSave)
                
                if !canSave {
                    Text("Please fill in all required fields")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "8A92A6"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color(hex: "FFF0F5").opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(PinkDrapeBackground().ignoresSafeArea())
        .onChange(of: line1) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 4 {
                addressAutocomplete.update(query: trimmed)
                showSuggestions = true
            } else {
                showSuggestions = false
            }
        }
    }
}

private struct ShippingInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    let iconColor: Color
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization? = .words
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "8A92A6"))
            
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                TextField(placeholder, text: $text)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "1A1D2B"))
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(autocapitalization)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: "F9FAFB"))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AddressResult {
    let line1: String
    let city: String
    let state: String
    let zip: String
    let country: String
}

final class AddressAutocomplete: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }
    
    func update(query: String) {
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }
    
    func select(_ completion: MKLocalSearchCompletion, completionHandler: @escaping (AddressResult?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let place = response?.mapItems.first?.placemark else {
                completionHandler(nil)
                return
            }
            
            let line1 = [place.subThoroughfare, place.thoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            let city = place.locality ?? ""
            let state = place.administrativeArea ?? ""
            let zip = place.postalCode ?? ""
            let country = place.country ?? "US"
            
            completionHandler(AddressResult(
                line1: line1.isEmpty ? completion.title : line1,
                city: city,
                state: state,
                zip: zip,
                country: country
            ))
        }
    }
}

// MARK: - Notification Manager
final class NotificationManager {
    static let shared = NotificationManager()
    
    enum PreferenceKeys {
        static let notificationsEnabled = "glowup.notifications.enabled"
        static let routineReminders = "glowup.notifications.routine"
        static let photoReminders = "glowup.notifications.photo"
    }
    
    enum Ids {
        static let routine = "glowup.routine.reminder"
        static let photo = "glowup.photo.checkin"
        static let routineMorning = "glowup.routine.morning"
        static let routineEvening = "glowup.routine.evening"
        static let exfoliationWeekly = "glowup.special.exfoliation"
        static let photoBiweekly = "glowup.photo.biweekly"
    }
    
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
    
    @discardableResult
    func syncScheduledNotifications(userId: String?) async -> Bool {
        let defaults = UserDefaults.standard
        let notificationsEnabled = defaults.object(forKey: PreferenceKeys.notificationsEnabled) as? Bool ?? true
        let routineReminders = defaults.object(forKey: PreferenceKeys.routineReminders) as? Bool ?? true
        let photoReminders = defaults.object(forKey: PreferenceKeys.photoReminders) as? Bool ?? true
        
        guard notificationsEnabled else {
            clearAll()
            return true
        }
        
        let permissionGranted = await ensureAuthorizationIfNeeded()
        guard permissionGranted else {
            clearAll()
            return false
        }
        
        if routineReminders {
            try? await scheduleRoutineReminders(userId: userId)
        } else {
            clearRoutineReminders()
        }
        
        if photoReminders {
            scheduleBiweeklyPhotoCheckins()
        } else {
            clearBiweeklyPhotoCheckins()
        }
        
        return true
    }
    
    func ensureAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
    
    func scheduleRoutineReminders(userId: String?) async throws {
        let center = UNUserNotificationCenter.current()
        clearRoutineReminders()
        
        let routineSummary = try await loadRoutineSummary(userId: userId)
        
        // Morning reminder (9:00 AM)
        var morning = DateComponents()
        morning.hour = 9
        morning.minute = 0
        let morningTrigger = UNCalendarNotificationTrigger(dateMatching: morning, repeats: true)
        let morningContent = UNMutableNotificationContent()
        morningContent.title = "Good morning ✨"
        morningContent.body = routineSummary.morning.isEmpty ? "Time for your morning routine." : routineSummary.morning
        morningContent.sound = .default
        morningContent.userInfo = ["destination": "routine"]
        let morningRequest = UNNotificationRequest(
            identifier: Ids.routineMorning,
            content: morningContent,
            trigger: morningTrigger
        )
        try await center.add(morningRequest)
        
        // Evening reminder (8:00 PM)
        var evening = DateComponents()
        evening.hour = 20
        evening.minute = 0
        let eveningTrigger = UNCalendarNotificationTrigger(dateMatching: evening, repeats: true)
        let eveningContent = UNMutableNotificationContent()
        eveningContent.title = "Wind down 🌙"
        eveningContent.body = routineSummary.evening.isEmpty ? "Time for your evening routine." : routineSummary.evening
        eveningContent.sound = .default
        eveningContent.userInfo = ["destination": "routine"]
        let eveningRequest = UNNotificationRequest(
            identifier: Ids.routineEvening,
            content: eveningContent,
            trigger: eveningTrigger
        )
        try await center.add(eveningRequest)
        
        // Weekly special reminder (Sunday 10:00 AM)
        var weekly = DateComponents()
        weekly.weekday = 1 // Sunday
        weekly.hour = 10
        weekly.minute = 0
        let weeklyTrigger = UNCalendarNotificationTrigger(dateMatching: weekly, repeats: true)
        let weeklyContent = UNMutableNotificationContent()
        weeklyContent.title = "Weekly glow reset"
        weeklyContent.body = "Exfoliation day — keep it gentle and consistent."
        weeklyContent.sound = .default
        weeklyContent.userInfo = ["destination": "routine"]
        let weeklyRequest = UNNotificationRequest(
            identifier: Ids.exfoliationWeekly,
            content: weeklyContent,
            trigger: weeklyTrigger
        )
        try await center.add(weeklyRequest)
    }
    
    func scheduleBiweeklyPhotoCheckins() {
        let center = UNUserNotificationCenter.current()
        let upcomingIds = (0..<6).map { "\(Ids.photoBiweekly)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: upcomingIds)
        
        // Schedule the next 6 biweekly Sundays at 8:00 PM
        let calendar = Calendar.current
        let now = Date()
        var next = nextSundayEvening(from: now)
        
        for idx in 0..<6 {
            let content = UNMutableNotificationContent()
            content.title = "Progress check‑in"
            content.body = "Time for your biweekly photo to track your glow."
            content.sound = .default
            content.userInfo = ["destination": "progress"]
            
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "\(Ids.photoBiweekly)-\(idx)",
                content: content,
                trigger: trigger
            )
            center.add(request)
            
            // Move forward 14 days
            next = calendar.date(byAdding: .day, value: 14, to: next) ?? next.addingTimeInterval(60 * 60 * 24 * 14)
        }
    }
    
    func clear(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
    
    func clearRoutineReminders() {
        clear(ids: [
            Ids.routineMorning,
            Ids.routineEvening,
            Ids.exfoliationWeekly
        ])
    }
    
    func clearBiweeklyPhotoCheckins() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let photoIds = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Ids.photoBiweekly) }
            guard !photoIds.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: photoIds)
        }
    }
    
    func clearAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    private func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
    
    private func nextSundayEvening(from date: Date) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 20
        components.minute = 0
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents) ?? date
    }
    
    private func loadRoutineSummary(userId: String?) async throws -> (morning: String, evening: String) {
        guard let userId else { return ("", "") }
        let result = try await SupabaseService.shared.getLatestRoutine(userId: userId)
        let routine = result?.inference?.routine ?? result?.summary.routine
        let morning = summarizeSteps(routine?.morning, prefix: "AM")
        let evening = summarizeSteps(routine?.evening, prefix: "PM")
        return (morning, evening)
    }
    
    private func summarizeSteps(_ steps: [RoutineStep]?, prefix: String) -> String {
        guard let steps, !steps.isEmpty else { return "" }
        let names = steps.prefix(3).map { step in
            if let product = step.product {
                return "\(step.name): \(product.name)"
            }
            return step.name
        }
        return "\(prefix): " + names.joined(separator: " • ")
    }
}

// MARK: - Delivery Tracking Manager
final class DeliveryTrackingManager {
    static let shared = DeliveryTrackingManager()
    private init() {}
    
    private var timer: Timer?
    private var isPolling = false
    private let statusDefaultsKey = "glowup.lastDeliveryStatus"
    private let orderDefaultsKey = "glowup.lastDeliveryOrderId"
    
    func startPolling(userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        if isPolling { return }
        isPolling = true
        
        Task { await pollOnce(userId: userId) }
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.pollOnce(userId: userId) }
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
        isPolling = false
    }
    
    @MainActor
    private func pollOnce(userId: String) async {
        do {
            let tracking = try await APIService.shared.getLatestOrderTracking(userId: userId)
            let statusKey = "\(tracking.orderId):\(tracking.status)"
            let lastStatus = UserDefaults.standard.string(forKey: statusDefaultsKey)
            let lastOrderId = UserDefaults.standard.string(forKey: orderDefaultsKey)
            
            if statusKey != lastStatus || tracking.orderId != lastOrderId {
                UserDefaults.standard.set(statusKey, forKey: statusDefaultsKey)
                UserDefaults.standard.set(tracking.orderId, forKey: orderDefaultsKey)
                postStatusNotification(for: tracking)
            }
        } catch {
            // No tracked order yet or temporary backend issue. Keep polling silently.
        }
    }
    
    private func postStatusNotification(for tracking: APIService.OrderTracking) {
        let content = UNMutableNotificationContent()
        content.title = "Order update (\(tracking.retailer.capitalized))"
        
        let statusText = tracking.status.replacingOccurrences(of: "_", with: " ").capitalized
        if let last = tracking.events.last?.message, !last.isEmpty {
            content.body = "\(statusText): \(last)"
        } else {
            content.body = "Your order is now \(statusText)."
        }
        content.sound = .default
        content.userInfo = [
            "destination": "delivery_tracking",
            "orderId": tracking.orderId,
            "trackingUrl": tracking.trackingUrl
        ]
        
        let request = UNNotificationRequest(
            identifier: "glowup.delivery.\(tracking.orderId).\(tracking.status)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Shared Store (Cart)
// ═══════════════════════════════════════════════════

final class CartManager: ObservableObject {
    // Dictionary-based store keyed by product ID
    @Published private var store: [String: CartItem] = [:]
    @Published var isSyncing = false
    
    // Track which product IDs have been modified locally but not yet persisted
    private var dirtyIds: Set<String> = []
    // Track which product IDs were removed locally (need DB delete on flush)
    private var removedIds: Set<String> = []

    /// Stable sorted array for SwiftUI ForEach
    var items: [CartItem] {
        store.values.sorted { $0.product.name < $1.product.name }
    }

    var totalPrice: Double {
        store.values.reduce(0) { $0 + ($1.product.price * Double($1.quantity)) }
    }

    var itemCount: Int {
        store.values.reduce(0) { $0 + $1.quantity }
    }

    func contains(productId: String) -> Bool {
        store[productId] != nil
    }

    func quantity(for productId: String) -> Int {
        store[productId]?.quantity ?? 0
    }

    // ── Immediate-persist methods (used when adding from product cards, chat, etc.) ──

    /// Add a product to cart and persist immediately
    func addToCart(_ product: InferenceProduct) {
        let pid = product.id
        if var existing = store[pid] {
            existing.quantity += 1
            store[pid] = existing
            persist(productId: pid, quantity: existing.quantity)
        } else {
            store[pid] = CartItem(product: product, quantity: 1)
            persist(productId: pid, quantity: 1)
        }
        // Clean from dirty/removed since we just persisted
        dirtyIds.remove(pid)
        removedIds.remove(pid)
    }

    /// Hard-remove and persist immediately
    func removeFromCart(productId: String) {
        store.removeValue(forKey: productId)
        dirtyIds.remove(productId)
        removedIds.remove(productId)
        removePersisted(productId: productId)
    }

    func clearCart() {
        store.removeAll()
        dirtyIds.removeAll()
        removedIds.removeAll()
        clearPersisted()
    }

    // ── Local-only methods (only change the number on screen) ──

    /// +1 locally — no DB call
    func incrementLocal(productId: String) {
        guard var item = store[productId] else { return }
        item.quantity += 1
        store[productId] = item
        dirtyIds.insert(productId)
    }

    /// −1 locally — removes item if qty hits 0. No DB call.
    func decrementLocal(productId: String) {
        guard var item = store[productId] else { return }
        let newQty = item.quantity - 1
        if newQty <= 0 {
            store.removeValue(forKey: productId)
            dirtyIds.remove(productId)
            removedIds.insert(productId)
        } else {
            item.quantity = newQty
            store[productId] = item
            dirtyIds.insert(productId)
        }
    }

    // ── Flush: persist all pending changes to DB ──

    /// Call this when the user dismisses the cart/quick-buy or taps Apple Pay
    func flushPendingChanges() {
        guard let userId = SessionManager.shared.userId else { return }
        
        // Persist updated quantities
        let toUpdate = dirtyIds
        for pid in toUpdate {
            if let item = store[pid] {
                let qty = item.quantity
                Task {
                    try? await APIService.shared.upsertCartItem(userId: userId, productId: pid, quantity: qty)
                }
            }
        }
        
        // Remove deleted items
        let toRemove = removedIds
        for pid in toRemove {
            Task {
                try? await APIService.shared.removeCartItem(userId: userId, productId: pid)
            }
        }
        
        dirtyIds.removeAll()
        removedIds.removeAll()
    }

    // ── Load from DB ──

    func loadCart(userId: String?) {
        guard let userId = userId else { return }
        isSyncing = true
        Task {
            do {
                let loaded = try await APIService.shared.getCart(userId: userId)
                await MainActor.run {
                    var dict: [String: CartItem] = [:]
                    for ci in loaded { dict[ci.product.id] = ci }
                    self.store = dict
                    self.isSyncing = false
                }
            } catch {
                await MainActor.run { self.isSyncing = false }
                #if DEBUG
                print("❌ Failed to load cart: \(error)")
                #endif
            }
        }
    }

    // ── Private persistence helpers ──

    private func persist(productId: String, quantity: Int) {
        guard let userId = SessionManager.shared.userId else { return }
        Task {
            try? await APIService.shared.upsertCartItem(userId: userId, productId: productId, quantity: quantity)
        }
    }

    private func removePersisted(productId: String) {
        guard let userId = SessionManager.shared.userId else { return }
        Task {
            try? await APIService.shared.removeCartItem(userId: userId, productId: productId)
        }
    }

    private func clearPersisted() {
        guard let userId = SessionManager.shared.userId else { return }
        Task {
            try? await APIService.shared.clearCart(userId: userId)
        }
    }
}

struct CartItem: Identifiable {
    let product: InferenceProduct
    var quantity: Int

    var id: String { product.id }
}

// ═══════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView(analysisResult: AnalysisResult(
            agents: [],
            summary: Summary(
                totalProducts: 10,
                totalCost: 150.0,
                overallConfidence: "0.85",
                routine: nil,
                personalized_tips: []
            ),
            inference: nil
        ))
    }
}
