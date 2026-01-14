import Foundation

enum PaperDetailsAPI {
    static let endpoint = URL(string: "https://x3o2rsjkbdoqe2alc4kkemewm40kdlkw.lambda-url.us-west-2.on.aws/")!

    struct LambdaEnvelope: Decodable {
        let statusCode: Int?
        let body: String?
    }

    struct BodyPayload: Decodable {
        let ok: Bool
        let source: String?
        let paper: PaperInfo
    }

    struct PaperInfo: Decodable, Encodable {
        let pdf_url: String
        let title: String?
        let abstract: String?
        let authors: String?
        let motivation: String?
        let experiment_setup: String?
        let methodology: String?
        let result: String?
        let conclusion: String?
        let survey: String?
        let page_count: Int?
        let used_pages: Int?
        let id: String?
        let created_at: String?
        let updated_at: String?
        let embedding_vector: [Double]?
    }

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func fetchPaperDetails(pdfURL: String) async throws -> BodyPayload {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "task": "get_paper_details",
            "payload": ["pdf_url": pdfURL]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw APIError(message: "HTTP \(http.statusCode). Raw: \(raw.prefix(500))")
        }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601

        // 1) Sometimes the Lambda URL might return the inner object directly.
        if let direct = try? dec.decode(BodyPayload.self, from: data) {
            if direct.ok { return direct }
            throw APIError(message: "Server responded ok=false")
        }

        // 2) Usual case: envelope { statusCode, body: "<json string>" }
        do {
            let env = try dec.decode(LambdaEnvelope.self, from: data)
            guard let bodyString = env.body, !bodyString.isEmpty else {
                let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                throw APIError(message: "Response missing 'body'. Raw: \(raw.prefix(500))")
            }

            // body can be JSON string OR a double-encoded JSON string. Handle both.
            let trimmed = bodyString.trimmingCharacters(in: .whitespacesAndNewlines)

            // 2a) normal: body is "{...}"
            if let bodyData = trimmed.data(using: .utf8),
               let parsed = try? dec.decode(BodyPayload.self, from: bodyData) {
                if parsed.ok { return parsed }
                throw APIError(message: "Server responded ok=false")
            }

            // 2b) double-encoded: body is "\"{\\\"ok\\\":true...}\""
            if let bodyData = bodyString.data(using: .utf8),
               let unwrapped = try? dec.decode(String.self, from: bodyData),
               let unwrappedData = unwrapped.data(using: .utf8),
               let parsed2 = try? dec.decode(BodyPayload.self, from: unwrappedData) {
                if parsed2.ok { return parsed2 }
                throw APIError(message: "Server responded ok=false")
            }

            throw APIError(message: "Could not decode body JSON. Body prefix: \(trimmed.prefix(300))")

        } catch let DecodingError.keyNotFound(key, ctx) {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw APIError(message: "Missing key '\(key.stringValue)' at \(ctx.codingPath.map { $0.stringValue }.joined(separator: "."))\nRaw: \(raw.prefix(500))")
        } catch let DecodingError.typeMismatch(type, ctx) {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw APIError(message: "Type mismatch \(type) at \(ctx.codingPath.map { $0.stringValue }.joined(separator: "."))\nRaw: \(raw.prefix(500))")
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw APIError(message: "Unexpected response format. Raw: \(raw.prefix(500))")
        }
    }
}

