import Foundation
import Security

/// Minimal client for Remail (https://remail.foo), used to share songs by email.
struct RemailClient {
    static let baseURL = URL(string: "https://remail.foo")!
    /// Raw attachment ceiling: the API caps base64 content at ~35 MB.
    static let maxAttachmentBytes = 25 * 1024 * 1024

    let apiKey: String

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Attachment {
        var filename: String
        var data: Data
        var contentType: String
    }

    /// One-line summary of `account.status` — whether sending is actually possible right now.
    func accountStatus() async throws -> String {
        let json = try await call("GET", "/v1/account", body: nil)
        let healthy = json["healthy"] as? Bool ?? false
        let ses = json["ses"] as? [String: Any]
        let production = ses?["production_access"] as? Bool ?? false
        let warnings = (json["warnings"] as? [Any])?.map { "\($0)" } ?? []
        var parts = [healthy ? "Healthy" : "Unhealthy"]
        parts.append(production ? "production sending" : "SES sandbox — only verified recipients receive mail")
        if let sent = ses?["sent_last_24_hours"] as? Int, let max = ses?["max_24_hour_send"] as? Int {
            parts.append("\(sent)/\(max) sent in 24 h")
        }
        parts += warnings
        if !healthy || !production || !warnings.isEmpty {
            throw Failure(message: parts.joined(separator: " · "))
        }
        return parts.joined(separator: " · ")
    }

    /// Sends one email; returns the Remail message id.
    func send(from: String, to: [String], replyTo: String?, subject: String,
              text: String, html: String, attachments: [Attachment]) async throws -> String {
        var body: [String: Any] = [
            "from": from, "to": to, "subject": subject, "text": text, "html": html,
            "attachments": attachments.map {
                ["filename": $0.filename, "content": $0.data.base64EncodedString(), "content_type": $0.contentType]
            },
        ]
        if let replyTo, !replyTo.isEmpty { body["reply_to"] = replyTo }
        let json = try await call("POST", "/v1/emails", body: body)
        guard let id = json["id"] as? String else { throw Failure(message: "Remail returned no message id.") }
        return id
    }

    private func call(_ method: String, _ path: String, body: [String: Any]?) async throws -> [String: Any] {
        guard !apiKey.isEmpty else { throw Failure(message: "Add a Remail API key in Settings → Email sharing.") }
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 120
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            // Errors carry a message plus next_actions with human-readable remediation reasons.
            let error = json["error"] as? [String: Any]
            var message = error?["message"] as? String ?? "Remail request failed (HTTP \(status))."
            let reasons = (error?["next_actions"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
            if !reasons.isEmpty { message += "\n\n" + reasons.joined(separator: "\n") }
            throw Failure(message: message)
        }
        return json
    }
}

/// Generic-password storage for secrets that shouldn't live in UserDefaults.
enum Keychain {
    private static func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func get(service: String, account: String) -> String? {
        var q = query(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, service: String, account: String) {
        let q = query(service, account)
        guard !value.isEmpty else { SecItemDelete(q as CFDictionary); return }
        let data = Data(value.utf8)
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
