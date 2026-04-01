import Foundation

final class LLMRefiner {
    enum Error: Swift.Error, LocalizedError {
        case invalidBaseURL
        case requestFailed(statusCode: Int, body: String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "The API Base URL is invalid."
            case let .requestFailed(statusCode, body):
                return "The API request failed (\(statusCode)): \(body)"
            case .emptyResponse:
                return "The model returned an empty response."
            }
        }
    }

    func refine(_ text: String, baseURL: String, apiKey: String, model: String, systemPrompt: String) async throws -> String {
        let endpoint = try chatCompletionsURL(from: baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text),
            ],
            temperature: 0
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.emptyResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw Error.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let content = decoded.choices.first?.message.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !content.isEmpty else {
            throw Error.emptyResponse
        }

        return content
    }

    func test(baseURL: String, apiKey: String, model: String, systemPrompt: String) async throws -> String {
        try await refine("请把 杰森 文件 发给我", baseURL: baseURL, apiKey: apiKey, model: model, systemPrompt: systemPrompt)
    }

    private func chatCompletionsURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let baseURL = URL(string: trimmed) else {
            throw Error.invalidBaseURL
        }

        if baseURL.path.hasSuffix("/chat/completions") {
            return baseURL
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw Error.invalidBaseURL
        }

        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }
        path += "/chat/completions"
        components.path = path

        guard let endpoint = components.url else {
            throw Error.invalidBaseURL
        }

        return endpoint
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: Content

        var text: String {
            switch content {
            case let .string(value):
                return value
            case let .parts(parts):
                return parts.compactMap(\.text).joined()
            }
        }
    }

    enum Content: Decodable {
        case string(String)
        case parts([Part])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .parts(try container.decode([Part].self))
            }
        }
    }

    struct Part: Decodable {
        let text: String?
    }
}
