import Foundation

// MARK: - Claude Model

enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case opus = "claude-opus-4-6"
    case sonnet = "claude-sonnet-4-6"
    case haiku = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: "Claude Opus 4.6"
        case .sonnet: "Claude Sonnet 4.6"
        case .haiku: "Claude Haiku 4.5"
        }
    }
}

// MARK: - Anthropic Service

enum AnthropicService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    struct Message {
        let role: String
        let content: String
    }

    // MARK: - Streaming

    /// Streams a response from the Claude API, calling `onDelta` for each text token.
    /// Returns the complete accumulated response text.
    static func streamMessage(
        apiKey: String,
        model: ClaudeModel,
        system: String,
        messages: [Message],
        maxTokens: Int = 4096,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw AnthropicError.httpError(httpResponse.statusCode, errorBody)
        }

        var fullText = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]" else { break }

            guard let data = json.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            if type == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String,
               deltaType == "text_delta",
               let text = delta["text"] as? String {
                fullText += text
                onDelta(text)
            }
        }

        return fullText
    }

    // MARK: - Errors

    enum AnthropicError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case noAPIKey

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Invalid response from API."
            case .httpError(let code, _):
                switch code {
                case 401: "Invalid API key. Please check your key in Settings."
                case 403: "Your API key does not have access to this model."
                case 429: "Rate limit exceeded. Please wait a moment and try again."
                case 529: "Claude is temporarily overloaded. Please try again shortly."
                default: "API error (HTTP \(code)). Please try again."
                }
            case .noAPIKey:
                "No API key configured. Add your Anthropic API key in Settings."
            }
        }
    }
}
