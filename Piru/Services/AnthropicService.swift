import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
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

enum AnthropicError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            "No API key configured. Add your key in Settings."
        case .invalidResponse:
            "Received an invalid response from the API."
        case .httpError(let code, let message):
            "API error (\(code)): \(message)"
        }
    }
}

enum AnthropicService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func streamMessage(
        messages: [[String: String]],
        system: String,
        model: ClaudeModel,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let body: [String: Any] = [
                        "model": model.rawValue,
                        "max_tokens": 4096,
                        "stream": true,
                        "system": system,
                        "messages": messages
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AnthropicError.invalidResponse
                    }

                    if httpResponse.statusCode != 200 {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        throw AnthropicError.httpError(httpResponse.statusCode, errorBody)
                    }

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else {
                            continue
                        }

                        if type == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           let deltaType = delta["type"] as? String,
                           deltaType == "text_delta",
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }

                        if type == "error",
                           let error = json["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            throw AnthropicError.httpError(0, message)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
