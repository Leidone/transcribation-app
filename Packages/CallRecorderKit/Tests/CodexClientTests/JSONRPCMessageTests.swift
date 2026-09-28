import Foundation
import Testing
@testable import CodexClient

struct JSONRPCMessageTests {
    private func line(_ json: String) -> Data { Data(json.utf8) }

    @Test("decodes a response")
    func decodesResponse() throws {
        let message = try JSONRPCMessage.decode(line: line(#"{"id":3,"result":{"ok":true}}"#))
        #expect(message == .response(id: 3, result: .object(["ok": .bool(true)])))
    }

    @Test("decodes an error response")
    func decodesError() throws {
        let message = try JSONRPCMessage.decode(line: line(#"{"id":4,"error":{"code":-32600,"message":"bad"}}"#))
        #expect(message == .error(id: 4, code: -32600, message: "bad"))
    }

    @Test("a message with method and no id is a notification")
    func decodesNotification() throws {
        let message = try JSONRPCMessage.decode(line: line(#"{"method":"turn/started","params":{"threadId":"t"}}"#))
        #expect(message == .notification(method: "turn/started", params: .object(["threadId": .string("t")])))
    }

    @Test("a message with method and id is a server request")
    func decodesServerRequest() throws {
        let message = try JSONRPCMessage.decode(line: line(#"{"id":9,"method":"item/x/requestApproval","params":{}}"#))
        #expect(message == .serverRequest(id: 9, method: "item/x/requestApproval", params: .object([:])))
    }

    @Test("garbage input is rejected with a typed error")
    func rejectsGarbage() {
        #expect(throws: CodexError.self) { try JSONRPCMessage.decode(line: line("not json")) }
        #expect(throws: CodexError.self) { try JSONRPCMessage.decode(line: line(#"{"foo":1}"#)) }
    }

    @Test("requests carry id and method but no jsonrpc member")
    func encodesRequestWithoutJSONRPCHeader() throws {
        let data = try JSONRPCMessage.encodeRequest(id: 1, method: "initialize", params: .object(["a": .number(1)]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text == #"{"id":1,"method":"initialize","params":{"a":1}}"#)
        #expect(!text.contains("jsonrpc"))
    }

    @Test("line buffer reassembles lines split across chunks")
    func lineBufferHandlesSplitChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("{\"a\":".utf8)).isEmpty)
        let lines = buffer.append(Data("1}\n{\"b\":2}\n".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
    }

    @Test("an id outside the Int range is not an integer instead of crashing")
    func hugeNumbersAreNotIntegers() throws {
        let huge = try JSONDecoder().decode(JSONValue.self, from: Data("1e300".utf8))
        #expect(huge.intValue == nil)
        #expect(JSONValue.number(42).intValue == 42)
    }

    @Test("line buffer ignores empty lines")
    func lineBufferSkipsEmptyLines() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("\n\n".utf8)).isEmpty)
    }
}
