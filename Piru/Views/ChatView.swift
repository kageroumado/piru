import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp) private var allMessages: [ChatMessage]

    var onOpenSettings: (() -> Void)? = nil

    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var streamingText = ""
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var conversationID = UUID()

    // MARK: - Computed Properties

    private var messages: [ChatMessage] {
        allMessages.filter { $0.conversationID == conversationID }
    }

    private var hasAPIKey: Bool {
        KeychainHelper.load() != nil
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    // MARK: - Body

    var body: some View {
        Group {
            if hasAPIKey {
                chatBody
            } else {
                setupPrompt
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    conversationID = UUID()
                } label: {
                    Image(systemName: "plus.bubble")
                }
                .disabled(isStreaming)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Setup Prompt

    private var setupPrompt: some View {
        ContentUnavailableView {
            Label("AI Chat", systemImage: "brain")
        } description: {
            Text("Chat with Claude about your medications, substances, and usage history.")
        } actions: {
            Button {
                onOpenSettings?()
            } label: {
                Text("Set Up API Key")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Text("Add your Anthropic API key in Settings to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chat Body

    private var chatBody: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
        }
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty && !isStreaming {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isStreaming && !streamingText.isEmpty {
                            MessageBubble(
                                role: "assistant",
                                content: streamingText
                            )
                            .id("streaming")
                        }

                        if isStreaming && streamingText.isEmpty {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .id("thinking")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: streamingText) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Ask about substances, interactions, dosing, or your usage history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isStreaming {
                if streamingText.isEmpty {
                    proxy.scrollTo("thinking", anchor: .bottom)
                } else {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about substances...", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Theme.accent : .secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: "user", content: text, conversationID: conversationID)
        modelContext.insert(userMessage)
        inputText = ""

        let history = messages.map {
            AnthropicService.Message(role: $0.role, content: $0.content)
        }

        let modelRaw = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? ClaudeModel.sonnet.rawValue
        let selectedModel = ClaudeModel(rawValue: modelRaw) ?? .sonnet

        guard let apiKey = KeychainHelper.load() else {
            errorMessage = AnthropicService.AnthropicError.noAPIKey.localizedDescription
            showingError = true
            return
        }

        isStreaming = true
        streamingText = ""

        Task {
            do {
                let recentEntries = ChatContextBuilder.fetchRecentEntries(context: modelContext)
                let dailyItems = ChatContextBuilder.fetchDailyItems(context: modelContext)
                let systemPrompt = ChatContextBuilder.buildSystemPrompt(
                    recentEntries: recentEntries,
                    dailyItems: dailyItems
                )

                let fullResponse = try await AnthropicService.streamMessage(
                    apiKey: apiKey,
                    model: selectedModel,
                    system: systemPrompt,
                    messages: history
                ) { delta in
                    Task { @MainActor in
                        streamingText += delta
                    }
                }

                let assistantMessage = ChatMessage(
                    role: "assistant",
                    content: fullResponse,
                    model: selectedModel.rawValue,
                    conversationID: conversationID
                )
                modelContext.insert(assistantMessage)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }

            isStreaming = false
            streamingText = ""
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let role: String
    let content: String

    init(message: ChatMessage) {
        self.role = message.role
        self.content = message.content
    }

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    private var isUser: Bool { role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? Color.secondary.opacity(0.15)
                        : Theme.accent.opacity(0.15)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
