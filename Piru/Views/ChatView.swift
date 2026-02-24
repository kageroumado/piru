import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("selectedClaudeModel") private var selectedModel = ClaudeModel.opus.rawValue

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var streamingTask: Task<Void, Never>?
    @State private var apiKey: String?
    @State private var showingKeyEntry = false
    @State private var keyInput = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if apiKey == nil {
                setupView
            } else {
                chatBody
            }
        }
        .onAppear {
            apiKey = KeychainHelper.load()
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            Text("AI Chat")
                .font(.title2.bold())

            Text("Chat with Claude about your dose history, medications, and harm reduction. You'll need an Anthropic API key to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingKeyEntry = true
            } label: {
                Label("Set Up API Key", systemImage: "key")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 40)

            Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                Text("Get an API key at console.anthropic.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .alert("Enter API Key", isPresented: $showingKeyEntry) {
            SecureField("sk-ant-...", text: $keyInput)
            Button("Save") {
                saveAPIKey()
            }
            Button("Cancel", role: .cancel) {
                keyInput = ""
            }
        } message: {
            Text("Paste your Anthropic API key. It will be stored securely in your device's Keychain.")
        }
    }

    // MARK: - Chat Body

    private var chatBody: some View {
        VStack(spacing: 0) {
            messageList

            if let errorMessage {
                errorBanner(errorMessage)
            }

            inputBar
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(messages.isEmpty && !isStreaming)
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isStreaming && (messages.isEmpty || messages.last?.role != .assistant) {
                            thinkingIndicator
                                .id("thinking")
                        }
                    }
                    .padding()
                }
            }
            .onChange(of: messages.last?.content) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("Ask me anything")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("I can help with dose timing, interactions, adherence, and harm reduction.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var thinkingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    // MARK: - Actions

    private func saveAPIKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainHelper.save(apiKey: trimmed)
        apiKey = trimmed
        keyInput = ""
    }

    private func newConversation() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        messages = []
        errorMessage = nil
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard let apiKey else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        isStreaming = true

        let model = ClaudeModel(rawValue: selectedModel) ?? .opus
        let systemPrompt = ChatContextBuilder.buildSystemPrompt(context: modelContext)

        let apiMessages = messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        streamingTask = Task {
            do {
                let stream = AnthropicService.streamMessage(
                    messages: apiMessages.dropLast(),
                    system: systemPrompt,
                    model: model,
                    apiKey: apiKey
                )

                for try await text in stream {
                    guard !Task.isCancelled else { break }
                    messages[assistantIndex].content += text
                }
            } catch {
                if !Task.isCancelled {
                    if messages[assistantIndex].content.isEmpty {
                        messages.remove(at: assistantIndex)
                    }
                    errorMessage = error.localizedDescription
                }
            }

            isStreaming = false
            streamingTask = nil
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            Text(message.content.isEmpty ? " " : message.content)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .textSelection(.enabled)

            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(Theme.accent)
            : AnyShapeStyle(.ultraThinMaterial)
    }
}
