#if os(macOS)
import Foundation
import os

public struct AccountState: Equatable, Sendable {
    public enum Method: String, Sendable {
        case chatgpt
        case apiKey
    }

    public let requiresOpenAIAuth: Bool
    public let method: Method?
    public let email: String?
    public let planType: String?

    /// An API-key account has neither email nor plan, so the sign-in method is what counts.
    public var isSignedIn: Bool { method != nil }

    init(result: JSONValue) {
        let account = result["account"]
        requiresOpenAIAuth = result["requiresOpenaiAuth"]?.boolValue ?? true
        method = account?["type"]?.stringValue.flatMap(Method.init(rawValue:))
        email = account?["email"]?.stringValue
        planType = account?["planType"]?.stringValue
    }
}

public struct LoginChallenge: Equatable, Sendable {
    public let loginID: String
    public let authURL: URL
}

/// Waits for `account/login/completed` of one login, racing it against a timeout.
enum LoginWait {
    static func completion(
        loginID: String,
        in notifications: AsyncStream<JSONRPCMessage>,
        timeout: Duration
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await message in notifications {
                    guard case .notification("account/login/completed", let params?) = message,
                          params["loginId"]?.stringValue == loginID
                    else { continue }
                    if params["success"]?.boolValue == true { return }
                    throw CodexError.loginFailed(params["error"]?.stringValue)
                }
                throw CodexError.processExited
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CodexError.loginTimedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}

/// JSON-RPC client for `codex app-server` (experimental protocol; `codex app-server generate-json-schema` prints its schema).
public actor AppServerClient {
    private let process: CodexProcess
    private let scratchDirectory: URL
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var subscribers: [UUID: AsyncStream<JSONRPCMessage>.Continuation] = [:]
    private var reader: Task<Void, Never>?

    public init(process: CodexProcess, scratchDirectory: URL) {
        self.process = process
        self.scratchDirectory = scratchDirectory
    }

    public func start(clientName: String, clientVersion: String) async throws {
        try process.start()
        let lines = process.lines
        reader = Task { [weak self] in
            for await line in lines { await self?.handle(line: line) }
            await self?.processEnded()
        }
        _ = try await request("initialize", params: .object([
            "clientInfo": .object(["name": .string(clientName), "version": .string(clientVersion)]),
        ]))
        try process.send(JSONRPCMessage.encodeNotification(method: "initialized", params: nil))
    }

    public func stop() {
        process.terminate()
        reader?.cancel()
    }

    // MARK: Account

    public func readAccount() async throws -> AccountState {
        AccountState(result: try await request("account/read", params: .object(["refreshToken": .bool(false)])))
    }

    /// Signs in with an OpenAI API key; Codex keeps it in its own credential store.
    public func loginWithAPIKey(_ key: String) async throws {
        _ = try await request("account/login/start", params: .object([
            "type": .string("apiKey"), "apiKey": .string(key),
        ]))
    }

    /// The models the signed-in account can use (empty when the server lists none).
    public func availableModels() async throws -> [ModelChoice] {
        let result = try await request("model/list", params: .object(["includeHidden": .bool(false)]))
        guard case .array(let entries)? = result["data"] else { return [] }
        return entries.compactMap { entry in
            guard let id = entry["model"]?.stringValue ?? entry["id"]?.stringValue else { return nil }
            return ModelChoice(
                id: id, name: entry["displayName"]?.stringValue ?? id, isDefault: entry["isDefault"]?.boolValue ?? false
            )
        }
    }

    /// Starts the browser sign-in; the caller opens `authURL`, then awaits `awaitLogin`.
    public func beginChatGPTLogin() async throws -> LoginChallenge {
        let result = try await request("account/login/start", params: .object(["type": .string("chatgpt")]))
        guard let loginID = result["loginId"]?.stringValue,
              let urlString = result["authUrl"]?.stringValue,
              let authURL = URL(string: urlString)
        else { throw CodexError.malformedMessage("login response without authUrl") }
        return LoginChallenge(loginID: loginID, authURL: authURL)
    }

    /// Waits for the browser sign-in; on timeout the pending login is cancelled on the server side.
    public func awaitLogin(
        _ challenge: LoginChallenge,
        notifications: AsyncStream<JSONRPCMessage>,
        timeout: Duration = .seconds(300)
    ) async throws {
        do {
            try await LoginWait.completion(loginID: challenge.loginID, in: notifications, timeout: timeout)
        } catch CodexError.loginTimedOut {
            await cancelLogin(challenge)
            throw CodexError.loginTimedOut
        }
    }

    /// Withdraws a pending browser sign-in; a failure is logged, the login simply expires on its own.
    public func cancelLogin(_ challenge: LoginChallenge) async {
        do {
            _ = try await request("account/login/cancel", params: .object(["loginId": .string(challenge.loginID)]))
        } catch {
            Logger.codex.error("could not cancel the login: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func logout() async throws {
        _ = try await request("account/logout", params: .null)
    }

    // MARK: Analysis

    /// Context Codex normally adds to every request (environment, permissions, apps, collaboration mode, project docs).
    /// A call analysis needs none of it.
    static let leanContextConfig: [String: JSONValue] = [
        "include_environment_context": .bool(false),
        "include_permissions_instructions": .bool(false),
        "include_apps_instructions": .bool(false),
        "include_collaboration_mode_instructions": .bool(false),
        "project_doc_max_bytes": .number(0),
        "web_search": .string("disabled"),
    ]

    /// Runs one ephemeral, read-only thread and returns the structured analysis with its token usage.
    ///
    /// Token-saving measures: the prompt is compact and (by default) replaces Codex's own agent prompt, reasoning
    /// effort is low, reasoning summaries are switched off, and a cheaper model can be chosen in the prompt.
    public func analyze(
        transcript: String,
        prompt: AnalysisPrompt = .standard,
        provider: ProviderSettings = .default
    ) async throws -> AnalysisOutcome {
        let (text, usage) = try await structuredTurn(
            input: transcript, prompt: prompt, provider: provider, schema: try CallAnalysis.outputSchema()
        )
        return AnalysisOutcome(analysis: try CallAnalysis.decode(from: text), usage: usage)
    }

    /// Answers a question about meetings in its own ephemeral, read-only thread. The person's model, reasoning
    /// effort and prompt replacement choices apply; the instructions are the question prompt's.
    public func answer(
        _ question: MeetingQuestion,
        prompt: AnalysisPrompt = .standard,
        provider: ProviderSettings = .default
    ) async throws -> AnswerOutcome {
        var questionPrompt = prompt
        questionPrompt.instructions = MeetingQuestion.instructions
        let (text, usage) = try await structuredTurn(
            input: question.input, prompt: questionPrompt, provider: provider, schema: try MeetingAnswer.outputSchema()
        )
        return AnswerOutcome(answer: try MeetingAnswer.decode(from: text), usage: usage)
    }

    /// One turn in a fresh thread whose final message must match `schema`; returns that message and the usage.
    private func structuredTurn(
        input: String, prompt: AnalysisPrompt, provider: ProviderSettings, schema: JSONValue
    ) async throws -> (String, TokenUsage?) {
        var threadParams: [String: JSONValue] = [
            "ephemeral": .bool(true),
            "sandbox": .string("read-only"),
            "approvalPolicy": .string("never"),
            "cwd": .string(scratchDirectory.path),
        ]
        threadParams[prompt.replacesAgentPrompt ? "baseInstructions" : "developerInstructions"] = .string(prompt.instructions)
        if let model = prompt.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            threadParams["model"] = .string(model)
        }
        var config: [String: JSONValue] = prompt.replacesAgentPrompt ? Self.leanContextConfig : [:]
        if case .object(let providerConfig)? = provider.threadConfig() {
            config.merge(providerConfig) { _, added in added }
        }
        if !config.isEmpty { threadParams["config"] = .object(config) }

        let thread = try await request("thread/start", params: .object(threadParams))
        guard let threadID = thread["thread"]?["id"]?.stringValue else {
            throw CodexError.malformedMessage("thread/start without thread id")
        }

        let events = notifications()
        _ = try await request("turn/start", params: .object([
            "threadId": .string(threadID),
            "input": .array([.object(["type": .string("text"), "text": .string(input)])]),
            "outputSchema": schema,
            "effort": .string(prompt.effort.rawValue),
            "summary": .string("none"),
        ]))

        var collector = TurnResultCollector(threadID: threadID)
        for await message in events {
            switch collector.consume(message) {
            case .pending: continue
            case .finished(let text): return (text, collector.usage)
            case .failed(let reason): throw CodexError.turnFailed(reason)
            }
        }
        throw CodexError.processExited
    }

    // MARK: Plumbing

    /// Subscribe before sending the request whose notifications you need.
    public func notifications() -> AsyncStream<JSONRPCMessage> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<JSONRPCMessage>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func request(_ method: String, params: JSONValue?) async throws -> JSONValue {
        let id = nextRequestID
        nextRequestID += 1
        let payload = try JSONRPCMessage.encodeRequest(id: id, method: method, params: params)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try process.send(payload)
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func handle(line: Data) {
        guard let message = try? JSONRPCMessage.decode(line: line) else {
            Logger.codex.error("dropped an unreadable line bytes=\(line.count)")
            return
        }
        switch message {
        case .response(let id, let result):
            pending.removeValue(forKey: id)?.resume(returning: result)
        case .error(let id, let code, let text):
            pending.removeValue(forKey: id)?.resume(throwing: CodexError.rpc(code: code, message: text))
        case .notification:
            for subscriber in subscribers.values { subscriber.yield(message) }
        case .serverRequest(let id, let method, _):
            // No approvals or tools are expected (read-only, never ask); refuse instead of hanging.
            Logger.codex.error("refused server request method=\(method, privacy: .public)")
            if let reply = try? JSONRPCMessage.encodeErrorReply(id: id, code: -32601, message: "unsupported") {
                try? process.send(reply)
            }
        }
    }

    private func processEnded() {
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values { continuation.resume(throwing: CodexError.processExited) }
        for subscriber in subscribers.values { subscriber.finish() }
        subscribers.removeAll()
    }
}
#endif
