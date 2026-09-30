import Foundation

/// Turns whatever a local model actually returned into a `LectureStructure`.
///
/// Local models wrap JSON in prose, in Markdown fences, or in reasoning tags,
/// and they disagree about key casing. Every one of those is recoverable, and
/// recovering is worth real effort here: the alternative is discarding a
/// lecture that cannot be recorded again.
public enum LectureStructureParser {
    public static func parse(_ raw: String) -> LectureStructure? {
        let cleaned = stripReasoning(raw)
        guard let json = firstJSONObject(in: cleaned),
              let data = json.data(using: .utf8) else { return nil }

        // Lenient decoding never throws, so trying camelCase first and
        // returning on success would quietly discard every snake_case field.
        // Decode both ways and keep whichever recovered more of the lecture.
        let camelCase = JSONDecoder()
        let snakeCase = JSONDecoder()
        snakeCase.keyDecodingStrategy = .convertFromSnakeCase

        let candidates = [
            try? camelCase.decode(LectureStructure.self, from: data),
            try? snakeCase.decode(LectureStructure.self, from: data)
        ]
            .compactMap { $0 }
            .map { $0.normalized() }
            .filter { !$0.isEmpty }

        return candidates.max { richness($0) < richness($1) }
    }

    /// The same recovery, for the smaller replies other stages ask for.
    ///
    /// Same two problems — prose around the JSON, and disagreement about key
    /// casing — so the same two defences, rather than a second, weaker parser
    /// that only handles the tidy case.
    public static func parse<T: Decodable>(_ raw: String, as type: T.Type) -> T? {
        let cleaned = stripReasoning(raw)
        guard let json = firstJSONObject(in: cleaned),
              let data = json.data(using: .utf8) else { return nil }

        if let decoded = try? JSONDecoder().decode(type, from: data) { return decoded }
        let snakeCase = JSONDecoder()
        snakeCase.keyDecodingStrategy = .convertFromSnakeCase
        return try? snakeCase.decode(type, from: data)
    }

    /// How much of the schema a decode actually recovered.
    static func richness(_ structure: LectureStructure) -> Int {
        var score = structure.topics.count
            + structure.keyPoints.count
            + structure.outline.count
            + structure.glossary.count
            + structure.formulas.count
            + structure.reviewQuestions.count
            + structure.actionItems.count
            + structure.uncertainties.count
        for value in [structure.title, structure.courseName, structure.courseCode, structure.category, structure.summary]
        where !value.isEmpty {
            score += 1
        }
        return score
    }

    /// Removes `<think>` style blocks that reasoning models emit before their
    /// answer, plus Markdown code fences around the payload.
    static func stripReasoning(_ raw: String) -> String {
        var value = raw
        for tag in ["think", "thinking", "reasoning", "scratchpad"] {
            while let open = value.range(of: "<\(tag)>", options: .caseInsensitive) {
                guard let close = value.range(of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<value.endIndex) else {
                    value = String(value[value.startIndex..<open.lowerBound])
                    break
                }
                value.removeSubrange(open.lowerBound..<close.upperBound)
            }
        }
        return value
    }

    /// Scans for the first complete `{ … }` object, respecting string literals
    /// and escapes so a brace inside a definition does not end the object.
    static func firstJSONObject(in text: String) -> String? {
        var depth = 0
        var start: String.Index?
        var insideString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]
            if insideString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    insideString = false
                }
                continue
            }
            switch character {
            case "\"":
                insideString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { break }
                depth -= 1
                if depth == 0, let start {
                    return String(text[start...index])
                }
            default:
                break
            }
        }
        return nil
    }
}
