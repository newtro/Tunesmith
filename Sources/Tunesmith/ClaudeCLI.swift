import Foundation

/// Runs the local `claude` CLI in print mode so the app can use the user's
/// Claude subscription (no API key). Do not pass `--bare`: it skips Keychain
/// credentials and reports "Not logged in".
struct ClaudeCLI {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let candidatePaths = [
        "~/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ].map { NSString(string: $0).expandingTildeInPath }

    static func locate(override: String?) -> URL? {
        if let o = override, !o.isEmpty, FileManager.default.isExecutableFile(atPath: o) {
            return URL(fileURLWithPath: o)
        }
        return candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    let executable: URL
    let model: String

    /// Returns `structured_output` (when a schema is given) or the plain `result` text.
    func run(system: String, prompt: String, schema: [String: Any]? = nil,
             onStart: ((Process) -> Void)? = nil) async throws -> Any {
        var args = [
            "-p",
            "--no-session-persistence",
            "--tools", "",
            "--output-format", "json",
            "--model", model,
            "--system-prompt", system,
        ]
        if let schema {
            let data = try JSONSerialization.data(withJSONObject: schema)
            args += ["--json-schema", String(data: data, encoding: .utf8)!]
        }
        // Prompt goes over stdin so text starting with "-" is never parsed as a flag.
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = args
        proc.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        // Make sure the CLI sees the same auth the user's shell does; strip anything
        // that could redirect it at an API-key backend.
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env.removeValue(forKey: "ANTHROPIC_BASE_URL")
        proc.environment = env

        let out = Pipe(), err = Pipe(), input = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = input

        return try await withCheckedThrowingContinuation { cont in
            proc.terminationHandler = { p in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    cont.resume(throwing: Failure(message: "claude exited \(p.terminationStatus): \(errText.isEmpty ? text : errText)".trimmingCharacters(in: .whitespacesAndNewlines).prefix(600).description))
                    return
                }
                if (json["is_error"] as? Bool) == true || p.terminationStatus != 0 {
                    cont.resume(throwing: Failure(message: (json["result"] as? String) ?? "claude reported an error"))
                    return
                }
                if schema != nil, let structured = json["structured_output"] {
                    cont.resume(returning: structured)
                } else if let result = json["result"] as? String {
                    cont.resume(returning: result)
                } else {
                    cont.resume(throwing: Failure(message: "claude returned no result"))
                }
            }
            do {
                try proc.run()
                onStart?(proc)
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
            } catch {
                cont.resume(throwing: Failure(message: "Could not launch claude: \(error.localizedDescription)"))
            }
        }
    }
}
