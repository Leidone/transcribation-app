import Foundation
import Localization

public enum CodexError: LocalizedError, Equatable {
    case malformedMessage(String)
    case rpc(code: Int, message: String)
    case processFailedToStart(String)
    case processExited
    case loginFailed(String?)
    case loginTimedOut
    case turnFailed(String)
    case invalidAnalysis(String)

    public var errorDescription: String? {
        switch self {
        case .malformedMessage(let detail):
            tr("Codex прислал нечитаемое сообщение (\(detail)).", "Codex sent an unreadable message (\(detail)).")
        case .rpc(_, let message):
            tr("Codex сообщил об ошибке: \(message)", "Codex reported an error: \(message)")
        case .processFailedToStart(let detail):
            tr("Не удалось запустить Codex: \(detail)", "Codex could not be started: \(detail)")
        case .processExited:
            tr("Codex неожиданно остановился.", "Codex stopped unexpectedly.")
        case .loginFailed(let detail):
            tr("Не удалось войти в OpenAI", "Signing in to OpenAI failed") + (detail.map { ": \($0)" } ?? ".")
        case .loginTimedOut:
            tr("Вход в OpenAI занял слишком много времени и был отменён. Попробуйте ещё раз.",
               "Signing in to OpenAI took too long and was cancelled. Please try again.")
        case .turnFailed(let detail):
            tr("Codex не смог обработать запрос: \(detail)", "Codex could not answer: \(detail)")
        case .invalidAnalysis(let detail):
            tr("Codex вернул неожиданный ответ (\(detail)).", "Codex returned an unexpected result (\(detail)).")
        }
    }
}

/// One line of the `codex app-server` stdio protocol (JSON-RPC 2.0 without the `jsonrpc` member).
public enum JSONRPCMessage: Equatable, Sendable {
    case response(id: Int, result: JSONValue)
    case error(id: Int, code: Int, message: String)
    case notification(method: String, params: JSONValue?)
    case serverRequest(id: Int, method: String, params: JSONValue?)

    public static func decode(line: Data) throws -> JSONRPCMessage {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: line)
        } catch {
            throw CodexError.malformedMessage("not valid JSON")
        }
        guard case .object = value else { throw CodexError.malformedMessage("not an object") }

        if let method = value["method"]?.stringValue {
            if let id = value["id"]?.intValue {
                return .serverRequest(id: id, method: method, params: value["params"])
            }
            return .notification(method: method, params: value["params"])
        }
        guard let id = value["id"]?.intValue else { throw CodexError.malformedMessage("missing id") }
        if let failure = value["error"] {
            return .error(
                id: id,
                code: failure["code"]?.intValue ?? 0,
                message: failure["message"]?.stringValue ?? "unknown error"
            )
        }
        guard let result = value["result"] else { throw CodexError.malformedMessage("missing result") }
        return .response(id: id, result: result)
    }

    public static func encodeRequest(id: Int, method: String, params: JSONValue?) throws -> Data {
        try encode(["id": .number(Double(id)), "method": .string(method)], params: params)
    }

    public static func encodeNotification(method: String, params: JSONValue?) throws -> Data {
        try encode(["method": .string(method)], params: params)
    }

    public static func encodeErrorReply(id: Int, code: Int, message: String) throws -> Data {
        try encode([
            "id": .number(Double(id)),
            "error": .object(["code": .number(Double(code)), "message": .string(message)]),
        ], params: nil)
    }

    private static func encode(_ members: [String: JSONValue], params: JSONValue?) throws -> Data {
        var object = members
        if let params { object["params"] = params }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JSONValue.object(object))
    }
}
