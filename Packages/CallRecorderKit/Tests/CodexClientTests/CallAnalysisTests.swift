import Foundation
import Testing
@testable import CodexClient

struct CallAnalysisTests {
    @Test("decodes an analysis with nullable task fields")
    func decodesValidAnalysis() throws {
        // Arrange
        let json = """
        {"summary":"Обсудили релиз","decisions":["Релиз в пятницу"],
         "tasks":[{"title":"Подготовить changelog","owner":"Анна","due":"2027-01-15","quote":null,"timestampSeconds":125.5}]}
        """

        // Act
        let analysis = try CallAnalysis.decode(from: json)

        // Assert
        #expect(analysis.tasks.first?.owner == "Анна")
        #expect(analysis.tasks.first?.quote == nil)
        #expect(analysis.tasks.first?.timestampSeconds == 125.5)
    }

    @Test("rejects an analysis without tasks")
    func rejectsMissingTasks() {
        #expect(throws: CodexError.self) {
            try CallAnalysis.decode(from: #"{"summary":"s","decisions":[]}"#)
        }
    }

    @Test("output schema is valid JSON and requires every property (strict mode)")
    func schemaRequiresEveryProperty() throws {
        // Arrange / Act
        let schema = try CallAnalysis.outputSchema()

        // Assert
        let rootProperties = try #require(propertyNames(schema))
        #expect(Set(rootProperties) == Set(requiredNames(schema)))

        let taskSchema = try #require(schema["properties"]?["tasks"]?["items"])
        let taskProperties = try #require(propertyNames(taskSchema))
        #expect(Set(taskProperties) == Set(requiredNames(taskSchema)))
        #expect(taskSchema["additionalProperties"]?.boolValue == false)
    }

    private func propertyNames(_ schema: JSONValue) -> [String]? {
        guard case .object(let properties)? = schema["properties"] else { return nil }
        return Array(properties.keys)
    }

    private func requiredNames(_ schema: JSONValue) -> [String] {
        guard case .array(let names)? = schema["required"] else { return [] }
        return names.compactMap(\.stringValue)
    }
}
